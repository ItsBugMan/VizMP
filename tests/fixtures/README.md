# FLAC fixture

`stereo-tones.flac` is generated test audio: three seconds of 44,100 Hz,
16-bit stereo PCM encoded losslessly as FLAC. Left: 220 Hz sine; right:
1,760 Hz sine; amplitude: 0.24. It contains no third-party recordings.
The generated audio is dedicated to the public domain under CC0-1.0.

Run `tests/flac_smoke.gd` with Godot's headless console to verify the native
decoder, external paths, library, queue, seeking, screensaver, FFT and PCM.
