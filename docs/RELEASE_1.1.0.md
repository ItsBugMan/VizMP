# VizMP 1.1.0 — Reactive Expansion

Seven visualizers, fourteen skins, and a steadier audio-reactive engine.

## New visualizers

- **Lightning Storm:** bass and beat onsets trigger branching lightning, HDR
  flashes, cloud illumination and lingering afterglow. Mid/treble energy adds
  forks, with bounded geometry and Low/Balanced/High quality presets.
- **ASCII Face Rain:** falling green character lights reveal an original
  portrait through an audio-driven luminance mask. Silence clears every RGB
  pixel to black; no static portrait layer remains visible.

Both modes work in the player, floating visualizer window, fullscreen, and
Windows screensaver. Existing visualizer IDs and saved screensaver selections
remain compatible.

## Audio and stability fixes

- Fixed lost FFT reactivity after inserting or moving the file equalizer:
  analysis now follows the current audio effect instance.
- Added an adjustable **0–8× audio sensitivity** multiplier.
- Added rendering-cadence exponential interpolation for shader audio bands.
- Removed audio-driven camera speed changes, geometry rotation, radius changes
  and discrete fold switching from the fractal tunnel. Bass now drives light
  and haze while camera motion remains smooth.

## Retro skins and deck controls

Eight new packages join the original six: **Y2K Chrome**, **Neon Ronin**,
**V12 Redline**, **Arsenal Titanium**, **Velvet Muse**, **Orbital EVA**,
**Sentinel Head**, and **Xeno Pod**. These add original themed artwork,
metallic/plastic/mech surface shading, chamfered frames, transport glyphs,
LCD readouts, and live theme changes in floating panels.

The visualizer starts hidden. To restore it, open **Settings / skin →
Visualizer settings… → Enable Visualizer Viewport**. The same modal includes
audio sensitivity. Both preferences are saved. **F11** opens fullscreen
directly; **Esc** returns to the previous deck state. Hiding the visualizer
suspends its processing and owned render targets, including nested buffers.

## Windows downloads and upgrading

- **VizMP_Setup_v1.1.0.exe:** installer with optional shortcuts and screensaver
  registration. Update an existing installation using the same destination
  and install scope.
- **VizMP_Windows_x64_v1.1.0.zip:** portable player, screensaver, native FLAC
  library, self-contained desktop audio helper, and customizable skin files.
  Extract the entire archive and keep its folders together.
- **SHA256SUMS.txt:** SHA-256 checksums for both downloads.

Existing user settings and music libraries remain in the user's data folder.
Installed clients can use **Settings / skin → Check for updates…**. Windows
x64 with DirectX 12 graphics is required; Godot and .NET do not need separate
installation. This release is unsigned.

## Validation and known limitations

The expansion, audio, UI, tunnel/city, galaxy, transport/library, screensaver,
and stereo oscilloscope suites passed on Godot 4.7.2. Actual Forward+/D3D12
rendering was exercised on an RTX 3070, including exact-black silence, bounded
bolts, theme propagation, fullscreen restoration, and hidden viewport cleanup.
Measured 1080p viewport GPU medians were approximately **1.5 ms for lightning**
and **0.4 ms for ASCII rain**; these exclude the rest of the application frame.

Clouds use a layered volume approximation. Window cutouts are visual frames
with rectangular input regions, rather than arbitrary OS hit masks. Winamp
`.wsz` import is not supported. The existing file oscilloscope has a capture
limitation on 7.1 output; its PCM/rendering suite passed with a stereo Dummy
audio driver. Use a stereo output device for that mode. The new FFT modes were
verified with the physical 7.1 endpoint. FLAC tags/embedded artwork and the
small Windows screensaver preview retain their existing limitations.

See [README](https://github.com/ItsBugMan/VizMP#readme) and
[implementation notes](https://github.com/ItsBugMan/VizMP/blob/v1.1.0/docs/REACTIVE_EXPANSION.md)
for controls, scene structure and technical details.
