# VizMP

Godot 4.7 audio visualizer foundation. Open `project.godot` and press **F6**
with `scenes/Main.tscn` open, or **F5** to launch the configured main scene.
Choose **Open audio**, or drop an MP3, OGG or WAV onto the application.
Choose **Live desktop audio** to capture the default Windows output instead.
See [Desktop loopback setup and validation](docs/DESKTOP_LOOPBACK.md).
Choose **Particle galaxy** for the GPU-driven 3D mode; see
[Galaxy scene, shaders and tuning](docs/PARTICLE_GALAXY.md).
**Fractal tunnel** and **Spectrum city** add raymarched flight and a GPU-driven
neon skyline; see [Tunnel and city scenes, shaders and tuning](docs/TUNNEL_AND_CITY.md).
**Vector CRT scope** displays actual stereo X-Y phase with green/amber
phosphor persistence; see [Oscilloscope scene, PCM routing and tuning](docs/OSCILLOSCOPE.md).
Windows `.scr` startup, settings, shuffled playback and input exit guards are
implemented; see [Windows screensaver setup and packaging](docs/WINDOWS_SCREENSAVER.md).
Panels can be resized, swapped, or detached. Use **Settings / skin** to change
the theme; see [Modular panels and custom skins](docs/MODULAR_UI_SKINS.md).
**F11** toggles fullscreen; **Escape** restores windowed mode.

## Implemented starter

- `scripts/audio/AudioAnalyzer.gd`: Master-bus analyzer autoload; 64 logarithmic
  frequency bands, stereo magnitude arrays, five broad bands, adaptive onset
  detection, fast attack/slow release smoothing and a decaying beat envelope.
- `scripts/visualizers/VisualizerShaderManager.gd`: one publisher for global
  shader uniforms and a compact 64×1 spectrum texture.
- `shaders/radial_visualizer.gdshader`: aspect-correct, antialiased radial
  spectrum with customizable colors and intensity.
- `scenes/Main.tscn`, `scripts/app/Main.gd`: runnable host and external audio loading.
- `scenes/visualizers/`: galaxy, raymarch tunnel, MultiMesh city and vector CRT scope.
- `docs/ARCHITECTURE.md`: contracts and extension plan for the complete application.

The project's existing Forward+ / D3D12 settings are preserved. Shader globals
and autoload order are already configured in `project.godot`. No plug-ins,
imported media or external assets are required for file mode. Desktop mode
uses the included WASAPI helper source and its pinned NAudio dependency.

## Audio contract

`AudioAnalyzer.spectrum_updated` fires after each analysis tick (up to 60 Hz).
Read `spectrum[0..63]`, `spectrum_left`, `spectrum_right`, `bass`, `mid`, `treble`,
`sub_bass`, `highs`, `volume`, and `beat_pulse` directly. Display levels are [0,1].
`raw_spectrum` contains uncompressed linear magnitudes. `volume_derivative` is
the change in mean linear spectral magnitude per second, not PCM RMS.
`beat_detected(strength)` signals an onset, not a BPM estimate or musical beat grid.
Consumers must not modify the shared arrays; copy only for history recording.

The analyzer creates/reuses an effect on Master at runtime. Let AudioAnalyzer
own this effect: rebuilding the bus layout while running requires explicit
rebinding. When mixing output effects, place analysis after your intended
processing stage; this starter appends it after existing effects.

File mode analyzes audio played **inside VizMP** through Master. Live desktop
mode uses AudioLoopbackManager's WASAPI capture and DesktopAnalysis bus.
Stereo FFT magnitudes cannot reconstruct phase; signed PCM is available from
`AudioLoopbackManager.pcm_frames` and its `pcm_updated` signal in desktop mode.
`StereoPCM` provides the shared signed PCM texture and correlation for either
file playback or desktop audio while the scope is active.

## Tuning

The autoload's exported controls set the dB display floor, smoothing speeds,
onset ratio, derivative threshold, silence gate and cooldown. Defaults are
starting points; master level and musical style affect transient sensitivity.
2048-point FFT balances latency and frequency resolution. At 44.1 kHz its
frequency spacing is about 21.5 Hz: 64 log display bins are not 64 independent
FFT coefficients, and the lowest bins can overlap the same FFT coefficients.
Use FFT_SIZE_4096 for better low-frequency discrimination at higher latency.

Broad ranges: sub-bass 20–60 Hz, bass 60–250 Hz, mid 250–4000 Hz,
treble 4000–12000 Hz, highs 12000–20000 Hz. Queries clamp to Nyquist.

## Validation

Validated with the installed **Godot 4.7.2** executable; 4.7.0 itself was not
available for execution. The source targets Godot 4.7 APIs.

```powershell
& '<path-to-godot.exe>' --headless --path . --script res://tests/audio_smoke.gd
```

The smoke test checks effect initialization, buffer dimensions, silent output,
onset/cooldown logic and a real 220 Hz PCM signal through Master and the FFT.
It briefly plays a low-level tone. A normal renderer launch also checks shader
compilation. Human listening and visual motion review remain useful for tuning.

## Roadmap boundary

Further 2D/3D modes, persistent playlist libraries and wallpaper integration
remain extension points. Desktop loopback, GPU galaxy, folded tunnel, spectrum
city, CRT phase scope, file PCM capture, basic playlists, file EQ, four-slot
docking, native panel windows, saved skins and Windows screensaver mode are implemented.

## API references

- [Spectrum analyzer instance](https://docs.godotengine.org/en/latest/classes/class_audioeffectspectrumanalyzerinstance.html)
- [Global shader uniforms](https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/shading_language.html#global-uniforms)
- [PCM capture effect](https://docs.godotengine.org/en/latest/classes/class_audioeffectcapture.html)

The online `latest` pages can describe newer development APIs; the installed
engine and runtime validation are the compatibility check for this starter.
