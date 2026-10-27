using System.Buffers.Binary;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using NAudio.CoreAudioApi;
using NAudio.Wave;

// Separate process: works with standard Godot builds, without Godot .NET.
// No files contain PCM. Only authenticated, local UDP packets carry audio.
internal static class Program
{
    private static int Main(string[] args)
    {
        string errorPath = "";
        try
        {
            if (args.Length != 4) return 2;
            int port = int.Parse(args[0]);
            byte[] token = Convert.FromHexString(args[1]);
            int parentId = int.Parse(args[2]);
            errorPath = args[3];
            if (token.Length != 16 || port is < 1 or > 65535) return 2;
            using var parent = Process.GetProcessById(parentId);
            using var socket = new UdpClient(AddressFamily.InterNetwork);
            socket.Connect(IPAddress.Loopback, port);
            using var enumerator = new MMDeviceEnumerator();
            uint sequence = 0;
            var sendLock = new object();

            // Keep packet ordering and sequence updates atomic across heartbeat
            // and capture threads. UDP never leaves the loopback adapter.
            void Send(byte[] packet, int bytes)
            {
                lock (sendLock)
                {
                    BinaryPrimitives.WriteUInt32LittleEndian(packet.AsSpan(20), sequence++);
                    socket.Send(packet, bytes);
                }
            }

            while (!parent.HasExited)
            {
                try
                {
                    using var device = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
                    using var capture = new DesktopCapture(device);
                    WaveFormat format = capture.WaveFormat;
                    var packet = Header(token, format.SampleRate, 0);
                    var heartbeat = Header(token, format.SampleRate, 0);
                    var (left, right) = ChannelWeights(device.AudioClient.MixFormat);
                    Exception? captureError = null;
                    int stopped = 0;
                    capture.RecordingStopped += (_, e) =>
                    {
                        captureError = e.Exception;
                        Interlocked.Exchange(ref stopped, 1);
                    };
                    capture.DataAvailable += (_, e) =>
                    {
                        try
                        {
                            int total = e.BytesRecorded / format.BlockAlign;
                            for (int start = 0; start < total; start += 256)
                            {
                                int count = Math.Min(256, total - start);
                                BinaryPrimitives.WriteInt32LittleEndian(packet.AsSpan(28), count);
                                for (int frame = 0; frame < count; frame++)
                                {
                                    float l = 0, r = 0;
                                    for (int ch = 0; ch < format.Channels; ch++)
                                    {
                                        int offset = (start + frame) * format.BlockAlign + ch * (format.BitsPerSample / 8);
                                        float sample = ReadSample(e.Buffer, offset, format);
                                        l += sample * left[ch];
                                        r += sample * right[ch];
                                    }
                                    WriteFloat(packet, 32 + frame * 8, l);
                                    WriteFloat(packet, 36 + frame * 8, r);
                                }
                                Send(packet, 32 + count * 8);
                            }
                        }
                        catch (Exception ex)
                        {
                            captureError = ex;
                            Interlocked.Exchange(ref stopped, 1);
                        }
                    };
                    capture.StartRecording();
                    File.WriteAllText(errorPath, "");
                    var checkDevice = Stopwatch.StartNew();
                    while (!parent.HasExited && Volatile.Read(ref stopped) == 0)
                    {
                        Send(heartbeat, 32); // No PCM during silence; still report readiness.
                        Thread.Sleep(250);
                        if (checkDevice.ElapsedMilliseconds < 1000) continue;
                        checkDevice.Restart();
                        using var active = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
                        if (active.ID != device.ID) break; // Reopen default device/format.
                    }
                    capture.StopRecording();
                    if (captureError != null) throw captureError;
                }
                catch (Exception ex)
                {
                    File.WriteAllText(errorPath, ex.Message);
                    // Unplug/replug and default-device changes recover without relaunch.
                    for (int i = 0; i < 10 && !parent.HasExited; i++) Thread.Sleep(100);
                }
            }
            return 0;
        }
        catch (Exception ex)
        {
            if (errorPath.Length > 0) File.WriteAllText(errorPath, ex.Message);
            return 1;
        }
    }

    private static byte[] Header(byte[] token, int rate, int frames)
    {
        byte[] packet = new byte[32 + 256 * 8];
        "VMP1"u8.CopyTo(packet);
        token.CopyTo(packet, 4);
        BinaryPrimitives.WriteInt32LittleEndian(packet.AsSpan(24), rate);
        BinaryPrimitives.WriteInt32LittleEndian(packet.AsSpan(28), frames);
        return packet;
    }

    private static void WriteFloat(byte[] bytes, int offset, float value) =>
        BinaryPrimitives.WriteSingleLittleEndian(bytes.AsSpan(offset), float.IsFinite(value) ? Math.Clamp(value, -1, 1) : 0);

    private static float ReadSample(byte[] data, int offset, WaveFormat format)
    {
        if (format.Encoding == WaveFormatEncoding.IeeeFloat && format.BitsPerSample == 32)
            return BinaryPrimitives.ReadSingleLittleEndian(data.AsSpan(offset));
        if (format.Encoding == WaveFormatEncoding.Pcm)
            return format.BitsPerSample switch
            {
                16 => BinaryPrimitives.ReadInt16LittleEndian(data.AsSpan(offset)) / 32768f,
                24 => ((data[offset] | data[offset + 1] << 8 | data[offset + 2] << 16) << 8 >> 8) / 8388608f,
                32 => BinaryPrimitives.ReadInt32LittleEndian(data.AsSpan(offset)) / 2147483648f,
                _ => throw new NotSupportedException("Unsupported PCM bit depth: " + format.BitsPerSample)
            };
        throw new NotSupportedException("Unsupported WASAPI mix format: " + format);
    }

    private static (float[], float[]) ChannelWeights(WaveFormat format)
    {
        int count = format.Channels;
        var left = new float[count];
        var right = new float[count];
        if (count == 1) { left[0] = right[0] = 1; return (left, right); }
        int mask = 0;
        if (format is WaveFormatExtensible)
        {
            // WAVEFORMATEXTENSIBLE: speaker mask at byte 20. NAudio 2.x
            // preserves this field but does not expose a public accessor.
            IntPtr pointer = WaveFormat.MarshalToPtr(format);
            try { mask = Marshal.ReadInt32(pointer, 20); }
            finally { Marshal.FreeHGlobal(pointer); }
        }
        if (mask == 0)
        {
            // Standard Windows channel order fallback.
            mask = count switch { 2 => 3, 4 => 0x33, 6 => 0x3f, 8 => 0x63f, _ => 0 };
            if (mask == 0) throw new NotSupportedException("Unknown multichannel speaker layout.");
        }
        int channel = 0;
        for (int bit = 0; bit < 32 && channel < count; bit++)
        {
            if ((mask & (1 << bit)) == 0) continue;
            (left[channel], right[channel]) = bit switch
            {
                0 => (1f, 0f), 1 => (0f, 1f), // FL, FR
                3 => (0.5f, 0.5f), // LFE contributes to bass visualization.
                4 or 6 or 9 or 12 or 15 => (0.707f, 0f),
                5 or 7 or 10 or 14 or 17 => (0f, 0.707f),
                _ => (0.707f, 0.707f) // Center and height-center channels.
            };
            channel++;
        }
        if (channel != count) throw new NotSupportedException("Inconsistent speaker mask.");
        float gain = 1f / Math.Max(1, Math.Max(left.Sum(), right.Sum()));
        for (int ch = 0; ch < count; ch++) { left[ch] *= gain; right[ch] *= gain; }
        return (left, right);
    }

    private sealed class DesktopCapture(MMDevice device) : WasapiCapture(device, false, 20)
    {
        protected override AudioClientStreamFlags GetAudioClientStreamFlags() =>
            base.GetAudioClientStreamFlags() | AudioClientStreamFlags.Loopback;
    }
}
