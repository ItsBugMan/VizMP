# Reactive visualizers and retro skin expansion

This document records the 1.1.0 expansion. Version 1.2.0 replaces its eight
prototype themed skins and removes their vector-art generator. See
[Illustrated skins and clarity update](ILLUSTRATED_SKINS.md) for the current
skin collection, ASCII rendering changes and window controls.

## Controls

The deck starts with its visualizer hidden. Settings / skin → Visualizer
settings… includes **Enable Visualizer Viewport** and an audio sensitivity
slider from 0 to 8×. Preferences persist in `user://visualizer.cfg`. F11 opens
an immersive view temporarily, and Esc restores the previous visibility state.
Closing or minimizing the visualizer does not stop audio analysis or playback.
Hidden visualizers disable their entire scene processing and all owned render
targets, including nested oscilloscope and glyph-atlas viewports. The scope
releases its PCM capture lease until restored. Detached windows retain their
ownership when hidden and return in the same place.

The main selector and screensaver settings offer seven modes. Existing mode
IDs 0–4 are preserved; Lightning Storm is 5 and ASCII Face Rain is 6.

## Audio and fractal stability

An actual source of lost reactivity was a retired FFT effect instance: adding
the Main Deck's EQ rebuilds Godot's audio effect instances. The analyzer now
resolves its current FFT instance by resource identity each analysis tick,
including after EQ detachment/redocking. A real 220 Hz regression fixture adds
an EQ before a silent FFT, then verifies that subsequent audio is detected.

`AudioAnalyzer` retains its reusable 64-bin buffers and separate exact-Hz bands.
Normalized display energy and beat strength use the clamped `sensitivity`
multiplier; raw linear spectrum data remains unchanged for detector accuracy.
Attack/release interpolation uses `1 - exp(-rate * delta)`. The global shader
publisher also interpolates its band and detail vectors at rendering cadence.

`signal_active` comes from the current unsmoothed FFT peak above the noise gate,
so a silence-sensitive visualizer does not have to wait for a smoothed level
to decay. FFT buffer latency still applies; it is not a sample-accurate mute
signal. Sensitivity zero closes this gate and suppresses new beats.

The tunnel camera follows a smooth audio-independent path and speed. Audio no
longer rotates geometry, changes corridor radius, or switches discrete fractal
fold counts. Quality alone controls folds. Bass/sub-bass instead change emission
and accumulated haze; mid/highs affect palette. This prevents a fixed camera
from seeing sudden geometry changes during a beat.

## Lightning scene

`scenes/visualizers/LightningVisualizer.tscn` → `Control` with its script builds
a shader-backed cloud rectangle behind cached bolt geometry. A beat signal or
rising smoothed sub-bass triggers a main strike, with a 250 ms cooldown. Mid and
treble add forks and secondary branches. Recursive midpoint displacement mixes
seeded fBm with random perturbations. Normalized paths are cached in screen
coordinates and rebuilt only for a strike or resize. No geometry is allocated
in the steady draw loop. At the current maximum parameters the geometry remains
under 1,100 line segments. Flashes include a second return-stroke peak and an
exponential afterglow.

`storm_clouds.gdshader` integrates front-to-back illuminated cloud slices using
four-octave noise. This is a bounded layered-volume approximation rather than a
full 3D fluid or cloud simulation. Low/Balanced/High use 4/6/9 slices and
64/128/256 main-bolt segments. The isolated HDR 2D viewport and its canvas
environment supply exposure changes, filmic tonemapping and glow. Low disables
glow and the widest bolt pass. Camera motion freezes cloud drift, not strikes.

## ASCII scene

`scenes/visualizers/AsciiRainVisualizer.tscn` → `Control` builds a 512×48
transparent glyph atlas in an isolated SubViewport rendered exactly once. A
single full-screen shader samples this atlas, the 64-bin spectrum texture, and
`assets/portraits/brow-mask.png`. Low/Balanced/High use 80/112/144 columns.
Columns have stable randomized speeds and changing hex glyphs. Their moving
trail is the illumination mask; portrait luminance is sampled only into glyph
ink. No full portrait layer is displayed. Audio energy controls trail coverage
and brightness, and each column reads a corresponding logarithmic frequency
bin. Areas without active glyphs remain black.

The hard `signal_active` uniform outputs RGB zero during silence even if the
interpolated energy remains positive. Bloom and the host's chromatic grade are
disabled for this mode, preserving black unlit pixels. The original fictional
adult portrait was generated for this project using imagegen and follows the
attached visual reference's forward-facing, over-the-brow composition. The
reference screenshot itself is not bundled or sampled.

## Skin packages

Eight new JSON + frame SVG + artwork SVG packages extend the original six.
Each uses `chrome.surface` (`metal`, `plastic`, `mech`), a relative
`chrome.artwork` texture path, and four `chrome.glyphs` transport strings. All
fields validate before a skin is committed. The optional chrome strip is
rendered by `SkinChrome.gd`, with the shared `skin_surface.gdshader` for brushed
highlights, ribbing, and moulded surfaces. Artwork is original editable vector
art; `scripts/tools/generate_expansion_skins.py` reproduces all eight packages
with Python's standard library. Existing version-1 skins remain compatible.

Nine-slice frame SVGs have transparent chamfered corners. Floating windows use
Godot's native transparent backgrounds; actual desktop compositing depends on
Windows and the graphics driver. Panels retain rectangular accessible input
regions. This implements shaped visual frames, not arbitrary polygonal OS hit
regions or Winamp `.wsz` import. The shared theme also supplies LCD readouts,
and glyph tooltips retain the plain transport action names.

## Validation

Run with the actual renderer, not headless, for GPU assertions:

```powershell
& $Godot --path . --script res://tests/expansion_smoke.gd
& $Godot --path . --script res://tests/advanced_modes_smoke.gd
& $Godot --path . --script res://tests/ui_smoke.gd
& $Godot --headless --path . --script res://tests/audio_smoke.gd
& $Godot --path . --audio-driver Dummy --script res://tests/oscilloscope_smoke.gd
```

The expansion test checks exact zero RGB over every silence pixel, visible
reactive output, bounded fork geometry across presets, sensitivity and smoothing,
all 14 skins, floating-window theme propagation, nested viewport suspension,
PCM lease release, fullscreen visibility restoration, and scene/atlas cleanup.
It writes preview captures and fixtures only under `.godot/`. Tests preserve
the user's skin and do not save deck preferences or layout.

Measured on this RTX 3070 with Godot 4.7.2 / D3D12 Forward+, the isolated
1920×1080 viewport medians were about 1.52 ms for high-quality lightning and
0.37 ms for high-quality ASCII rain. These are viewport GPU timings, not total
application frame times or a guaranteed frame rate.

The existing file oscilloscope has a separate surround-output limitation:
Godot's AudioEffectCapture mixes multiple stereo-pair effect instances into
one resource FIFO on this machine's 7.1 endpoint, and the most recent window
can contain silent surround pairs. The scope passes its actual PCM/rendering
suite with the stereo Dummy audio driver; that does not validate scope capture
on the physical 7.1 endpoint. The new FFT-based modes were verified with that
physical endpoint. Using a stereo output device avoids this existing scope
limitation. Desktop loopback has its own stereo PCM source.
