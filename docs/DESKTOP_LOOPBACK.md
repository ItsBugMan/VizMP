# Priority 1: Windows desktop audio

Implemented and integrated into the existing Main scene. The following
modules are also implemented; see `PARTICLE_GALAXY.md` and `MODULAR_UI_SKINS.md`.

## Run it

1. Open this project's `project.godot` in Godot **4.7.2**.
2. The helper is already built locally in `bin/loopback/VizMPLoopback.exe`.
   On a fresh checkout, install the **.NET 10 SDK** and run from the project:

   ```powershell
   ./native/build-loopback.ps1
   ```

   The first build restores pinned NAudio.Wasapi 2.2.1 and its dependencies
   from NuGet. `packages.lock.json` records the resolved package hashes.
   The resulting Windows x64 helper includes its .NET runtime. Neither the
   end user nor Godot needs a .NET installation or the Godot .NET edition.
3. Press **F5**, start Spotify, YouTube, or a game, and press **Live desktop audio**.
4. The status changes from connecting to **LIVE DESKTOP / … Hz** when PCM arrives.
   During silence it reports that it is waiting for system audio.
5. Release the toggle to resume file playback at its paused position. A file
   that was already paused stays paused. Opening/dropping a valid file also
   returns to file mode. The pause button is disabled during live capture.

Capture follows the Windows **default multimedia output endpoint**, including
default-output changes (checked once per second). Set Windows' default output
to the device playing the apps you want to visualize. Per-app output routing
to another endpoint will not be captured. Godot's own output-device setting
does not choose the loopback endpoint.

## Why there is a native helper

`AudioEffectCapture` is an AudioEffect resource attached to a bus, not a node
that opens Windows output devices. Godot's ordinary input-device list is not
an enumeration of WASAPI render-endpoint loopback devices.

The helper opens the default render endpoint using shared-mode WASAPI
loopback. No Stereo Mix, virtual cable, microphone permission, or microphone
input is required. Keep `audio/driver/enable_input` disabled unless another
feature explicitly needs a microphone. Protected content and audio paths
that bypass Windows' shared mixer may not be available to capture.

Microsoft reference: https://learn.microsoft.com/en-us/windows/win32/coreaudio/loopback-recording
Godot reference: https://docs.godotengine.org/en/latest/classes/class_audioeffectcapture.html

## Signal path and scene setup

```text
Windows shared output mix
  -> native/LoopbackBridge (WASAPI, 20 ms capture buffer)
  -> local UDP: stereo float32 PCM at the endpoint's native sample rate
  -> AudioLoopbackManager / DesktopPCM (AudioStreamPlayer + AudioStreamGenerator)
  -> DesktopAnalysis bus: AudioEffectCapture -> AudioEffectSpectrumAnalyzer
  -> DesktopSilentSink bus: MUTED
  -> Master

AudioAnalyzer reads DesktopAnalysis's FFT in live mode, Master's FFT in file mode.
VisualizerShaderManager and radial_visualizer.gdshader keep their existing API.
```

`default_bus_layout.tres` is Godot's automatically loaded default layout:

- **Master**: normal file audio output; analyzer managed by AudioAnalyzer.
- **DesktopSilentSink**: sends to Master, muted.
- **DesktopAnalysis**: sends to DesktopSilentSink, unmuted at 0 dB, capture
  effect first (250 ms ring), then 2048-point spectrum analysis (250 ms history).

Muting the sink ensures captured system audio cannot feed back to the output.
Leave analysis at full gain. Do not solo DesktopAnalysis or unmute its sink.
PCM goes straight into Godot's native audio pipeline. The capture effect taps
that same PCM for consumers; it is not played a second time to reach the FFT.
The loopback bridge does not implement FFT or iterate individual samples in
GDScript. When the vector scope is active, StereoPCM additionally packs a
bounded recent PCM window for the GPU; see `OSCILLOSCOPE.md`.

Autoload order in Project Settings -> Globals -> Autoload:

1. `ScreensaverManager`: `res://scripts/app/ScreensaverManager.gd`
2. `AudioAnalyzer`: `res://scripts/audio/AudioAnalyzer.gd`
3. `AudioLoopbackManager`: `res://scripts/audio/AudioLoopbackManager.gd`
4. `StereoPCM`: `res://scripts/audio/StereoPCM.gd`
5. `VisualizerShaderManager`: `res://scripts/visualizers/VisualizerShaderManager.gd`
6. `SkinManager`: `res://scripts/ui/SkinManager.gd`

No manual Main scene changes are needed: `scripts/app/Main.gd` builds the
toggle and registers the existing `$Player`. For another scene, register its
file player after it enters the tree:

```gdscript
AudioLoopbackManager.register_file_player($Player)
var result: Error = AudioLoopbackManager.set_mode(AudioLoopbackManager.Mode.DESKTOP)
if result != OK:
    push_warning(AudioLoopbackManager.status)
# Later:
AudioLoopbackManager.set_mode(AudioLoopbackManager.Mode.FILE)
```

`AudioAnalyzer.set_analysis_bus(bus_name)` reuses the selected bus's FFT,
clears display levels and resets onset history. Shader uniforms, 64 bins,
stereo magnitudes, smoothing, and five frequency bands remain unchanged.
Avoid replacing the bus layout while capture is running.

## PCM and diagnostics API

- `mode_changed(mode)`: selected FILE or DESKTOP mode; starting desktop means
  the helper was launched, not that the output endpoint is already ready.
- `status_changed(message)`: connecting, live, silence, device loss, or error.
- `pcm_updated`: consume `pcm_frames` (`PackedVector2Array`, x=L and y=R),
  sampled at **AudioServer.get_mix_rate()** after Godot resampling. Copy the
  array if retaining it across updates. The manager drains capture continuously.
- `sample_rate`: source endpoint rate, which can differ from the PCM tap rate.
- `received_frames`: source frames successfully queued in the generator.
- `dropped_packets`: observed transport sequence gaps; duplicates and reordered
  packets are ignored. Initial packets lost before the first received packet
  cannot be counted.
- `dropped_frames`: incoming frames affected by generator overrun recovery.
- `capture_discarded_frames`: audio-thread tap overflows since initialization;
  this engine counter is cumulative across desktop sessions.

No PCM is recorded to disk. A random per-session token and loopback-only UDP
binding prevent accidental cross-talk between concurrent VizMP instances.
Packets have a 32-byte little-endian header: `VMP1`, 16 token bytes, uint32
sequence, uint32 source rate, uint32 frame count, followed by interleaved
float32 L/R. At most 256 frames per packet; zero-frame packets are heartbeats.
This token isolates sessions; it is not protection against another process
already able to inspect the user's process arguments.

Main-thread packet work is bounded and old backlog is dropped after stalls.
The generator holds at most about 120 ms of source audio; this is buffer
capacity, not a guaranteed latency. End-to-end delay also includes WASAPI,
render cadence, FFT windowing, and smoothing. Profile on the target machine.
The RTX 3070 has no additional GPU work in this module.

The helper handles mono/stereo PCM/float mix formats and downmixes common
surround layouts to stereo with headroom. It reopens the default endpoint on
changes or capture errors. Endpoint disconnection retains desktop mode and
reports waiting; playback recovers when an endpoint returns. A terminated
helper returns VizMP to file mode. Switching to file mode kills the helper;
the helper also watches the parent process to prevent orphan capture.

## Validation

From the project directory, using the installed console executable:

```powershell
$engine = 'D:/Godot Engine/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $engine --headless --path . --script res://tests/audio_smoke.gd
& $engine --headless --audio-driver WASAPI --path . --script res://tests/loopback_smoke.gd
```

The loopback test briefly plays low-level stereo tones from a **separate
process**. Use a quiet default output for its spectral assertions. Explicit
WASAPI selection matters: ordinary headless Godot uses its Dummy audio driver,
which can run internal FFTs but cannot produce actual Windows system output.

The test checks external capture, nonzero PCM, bass response, stereo frequency
separation, output isolation, pause restoration, FFT rebinding, and helper
termination. The original audio smoke checks file audio and onset/cooldown.

Manual acceptance: test your music/browser/game, silence/resume, switch output
devices, unplug/reconnect the endpoint, and confirm the toggle resumes your
track correctly. Device switching/reconnection and long sessions require this
hardware acceptance pass; the automated tone test does not cover them.

## Exporting

Build the helper first. After a Windows x64 Godot export, copy the entire
`bin/loopback` directory beside the exported VizMP executable, naming the
directory `loopback`. The manager resolves `loopback/VizMPLoopback.exe` beside
the exported executable (not inside the PCK). The build copies `NAudio-LICENSE.txt`,
the .NET runtime `LICENSE.TXT` and `THIRD-PARTY-NOTICES.TXT` into that folder;
include them when distributing. The helper
source/build outputs are excluded from Godot imports with `.gdignore` files;
generated binaries are ignored by Git. Standard Godot x64 export templates
work; distributing a Godot .NET build is unnecessary.

## Files

- `scripts/audio/AudioLoopbackManager.gd`: mode/capture lifecycle, bounded PCM
  transport, generator, tap draining, diagnostics, error reporting.
- `scripts/audio/AudioAnalyzer.gd`: selectable FFT bus, preserving public API.
- `default_bus_layout.tres`: isolated PCM capture and FFT chain.
- `scripts/app/Main.gd`: integrated toggle and file playback coordination.
- `native/LoopbackBridge/Program.cs`: Windows output capture and device recovery.
- `native/LoopbackBridge/LoopbackBridge.csproj`, `packages.lock.json`: helper build.
- `native/build-loopback.ps1`: self-contained Windows build.
- `tests/loopback_smoke.gd`, `tests/loopback_tone.gd`: real system capture test.
