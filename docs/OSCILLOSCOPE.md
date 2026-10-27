# Vector CRT oscilloscope — Godot 4.7.2

## Run it

Press **F5**, choose **Vector CRT scope** in the Visualizer selector, and play
a file or enable **Live desktop audio**. Choose **Green phosphor** or **Amber
phosphor** beside the quality selector. Camera motion is disabled for this
mode; no artificial rotation is applied to measured phase geometry.

The scope uses signed raw stereo PCM: **Left -> X**, **Right -> Y**, with
positive right-channel amplitude drawn upward. Identical channels produce
an ascending diagonal, opposite channels a descending diagonal, quadrature
signals a circle, and different frequency ratios classic Lissajous figures.
Music generally produces a moving cloud of phase-correlated traces.

The readout reports the active source, DC-removed Pearson correlation, and
the duration of the current trace window. Correlation is +1 for matching
channels, -1 for polarity inversion, and near zero for a sufficiently long
quadrature window or unrelated channels. Silence and single-channel audio
show **—**, because phase correlation is undefined when either channel has
negligible variance. This is a short-window correlation display, not a phase
angle estimator or calibrated laboratory instrument.

## Scene structure

`res://scenes/visualizers/Oscilloscope.tscn` is independently runnable with F6.
The shared audio autoloads and default bus layout must remain configured.

```text
Oscilloscope (Control, Oscilloscope.gd)
  PhosphorBuffer (SubViewport, 2D HDR, transparent clear, retained color)
    Decay (ColorRect, phosphor_decay.gdshader, normal alpha blending)
    Beam (MeshInstance2D, static ribbon, oscilloscope_beam.gdshader, additive)
  CRT (ColorRect, crt_oscilloscope.gdshader)
  Readout (Label, updated at 10 Hz)
```

The main VisualizerHost creates the scope inside its existing output
SubViewport, with unused 3D rendering disabled. It frees that viewport and
the nested phosphor target when switching away. Detaching/redocking moves
the same scene; capture leases are released/reacquired on tree exit/entry,
and old phosphor history is cleared at that boundary. It does not start a
second audio session or native loopback helper.

## Raw PCM routing

The new `StereoPCM` autoload is the single consumer-facing PCM texture service.
It never reconstructs samples from FFT magnitudes and does not smooth the
left/right samples independently.

File playback:

```text
AudioStreamPlayer -> Master [file EQ -> File PCM capture -> existing FFT]
                                    |                      |
                                StereoPCM              AudioAnalyzer
```

The default bus layout now contains a normally disabled AudioEffectCapture
on Master. StereoPCM enables it only while the scope has a consumer and file
mode is selected. The file EQ is inserted before this tap. Capture occurs
before the bus's final output volume/mute, so the scope measures the audio
on that bus rather than the calibrated speaker volume.

Desktop capture:

```text
WASAPI helper -> DesktopAnalysis [existing capture + FFT] -> muted sink
                                      |
                          AudioLoopbackManager owns get_buffer()
                                      |
                            pcm_updated / pcm_frames
                                      |
                                  StereoPCM
```

StereoPCM subscribes to the existing desktop PCM notification. It does not
call get_buffer() a second time on that effect, which would steal samples
from the loopback manager. Its own Master tap is disabled in desktop mode.

Both paths publish at **AudioServer.get_mix_rate()**, after Godot's normal
resampling. The native Windows endpoint's source rate can differ. Stereo
sample pairs stay together through capture, history, texture packing and
GPU lookup, preserving their relative phase and amplitudes.

Autoload order in `project.godot`:

1. ScreensaverManager (startup dispatch; inactive during normal scope use)
2. AudioAnalyzer
3. AudioLoopbackManager
4. StereoPCM (`res://scripts/audio/StereoPCM.gd`)
5. VisualizerShaderManager
6. SkinManager

AudioLoopbackManager processes at priority -10, StereoPCM at -5, and the
scope at the normal priority. Captured input is published before the scope
updates beam uniforms. No new global shader parameters are needed.

## Vector rendering and memory

StereoPCM owns an 8,192-frame circular history and one fixed **2048x1 RG32F**
ImageTexture: `.r` is signed Left and `.g` signed Right. Its active display
window is 512, 1024 or 2048 consecutive samples. Only the newest window is
packed/uploaded when new PCM arrives. Samples are not logarithmically
compressed, converted to display magnitudes, or temporally decimated.

The beam is an indexed triangle ribbon. Static vertices encode segment index
and ribbon side. The vertex shader samples each segment's two PCM endpoints,
maps L/R to canvas coordinates, and extrudes a thin strip perpendicular to the
segment. A Gaussian cross-section supplies a bright core and antialiased
edge; additive blending handles intersections and repeated traces.

No line nodes, meshes, materials, ImageTextures or geometry arrays are
created each frame. The mesh is rebuilt only on an explicit quality change.
Its custom AABB includes the actual GPU-displaced drawing area. PCM ring,
packing array, Image, texture and mesh resources are reused during playback.

This is bounded allocation, not a claim of zero allocation: Godot's capture
API returns packed chunks and texture uploads can copy packed data internally.
The maximum PCM upload is a fixed 16 KB per update. HUD strings update at
10 Hz; weak-owner cleanup runs once per second. GDScript uses reference
counting; the design avoids a recurring geometry/object allocation workload.

Automatic gain uses **one common gain** for both channels. A fast common
ceiling prevents gain overshoot from clipping a new loud transient, while
gain increases recover gradually. Relative stereo amplitude is preserved.
For a fixed scale, disable `automatic_gain` on Oscilloscope and set
`manual_gain`; excessive manual gain clips at the display boundary.

## Real phosphor persistence

PhosphorBuffer uses `use_hdr_2d=true`. On creation, quality changes, track
changes and source resets it uses `CLEAR_MODE_ONCE`; Godot then switches it
to `CLEAR_MODE_NEVER`. Transparent clearing initializes RGB to true black,
independent of the project's default clear color.

Every frame, Decay draws black with:

```text
alpha = 1 - exp(-delta / persistence_seconds)
```

Normal alpha blending therefore multiplies the retained color by
`exp(-delta / persistence_seconds)`. The additive beam is drawn afterward.
Beam exposure scales with frame delta and the point budget, so changing FPS
does not simply double brightness. Large frame stalls cap new beam exposure.

This is the alpha-decay accumulation architecture: the previous HDR color
attachment is retained by the render pass. **No shader samples the texture
it is currently writing.** There is no recursive screen-texture feedback,
CPU image readback, trail snapshot stack, or per-frame render-target creation.
CRT samples the completed child viewport in the normal parent pass.

`persistence_seconds` defaults to 0.3 seconds and is the exponential time
constant, not a hard lifetime. Ordinary silence lets the trail fade. If an
audio bus stops producing frames for 120 ms, StereoPCM blanks stale input
without erasing afterglow. Source/track changes explicitly clear old history
so unrelated PCM windows are not connected into a false vector segment.

## CRT post-processing

`shaders/crt_oscilloscope.gdshader` reads the phosphor buffer with linear
filtering and adds:

- aspect-correct radial barrel/fisheye distortion;
- eight neighboring bloom taps plus the center sample;
- soft exposure compression and high-intensity core whitening;
- green or amber phosphor tint, applied after accumulation;
- a static graticule and center axes;
- fine horizontal scanlines;
- an RGB triad/dot shadow mask;
- corner vignette and rounded glass-edge falloff.

The palette can change immediately without reallocating or recoloring the
stored trail. The grid is drawn in the final pass, so it remains crisp and
does not burn into the afterglow. Aspect correction gives L and R the same
pixel scale and preserves circular quadrature traces across panel shapes.
Mask/scanline patterns are defined in the presentation viewport's pixels.

## RTX 3070 quality budgets

- **Low:** 512 raw points, 1,022 ribbon triangles, 384x384 HDR history.
- **Balanced:** 1,024 points, 2,046 triangles, 512x512 HDR history.
- **High:** 2,048 points, 4,094 triangles, 768x768 HDR history.

At 48 kHz these windows are about 10.7, 21.3 and 42.7 ms respectively; at
other mix rates the readout calculates the corresponding time. Increasing
quality shows a longer consecutive sample window and uses a sharper history
target. It does not change audio playback or add CPU interpolation.

The final CRT pass runs at panel resolution; the phosphor target remains
bounded regardless of window size. There are no lights, shadow passes,
particle systems or expensive 3D effects. Balanced is the starting preset
for the RTX 3070. Measure full-window GPU time at the intended resolution,
especially at 4K where the final bloom/CRT pass shades more pixels.

The newest-window display is not an archival recorder: at low FPS some
intermediate audio may never be shown, and a 512-point window may not contain
an entire very-low-frequency cycle. Use High for longer bass trajectories.

## Reuse and API

Main.gd registers **Vector CRT scope**, the palette selector and disabled
camera control. Existing mode IDs are preserved; scope is ID 4:

```gdscript
visualizer_host.set_mode(visualizer_host.Mode.SCOPE)
visualizer_host.set_quality(1)
visualizer_host.set_scope_palette(0) # 0=Green, 1=Amber
```

For another host, instance Oscilloscope.tscn under your canvas viewport and
call `set_quality(index)` / `set_palette(index)` after it enters the tree.
Keep the autoloads and Master capture layout in place. The scope acquires
and releases StereoPCM automatically.

StereoPCM exposes `pcm_texture`, `texture_frame_count`, `sample_rate`, `peak`,
`rms`, `correlation`, `correlation_valid`, `sequence` and capture diagnostics.
`stream_reset` invalidates source history; `texture_updated` announces new
PCM. Its `set_window_size()` configures the one active host's shared display
window. Do not independently drain its owned AudioEffectCapture or mutate
the shared texture. Runtime bus-layout replacement requires explicit rebinding,
as with the project's existing analyzer.

Main calls `StereoPCM.reset()` on track loads. Do the same from future seek
or source-change code. Keep the existing FFT/reset logic as well: PCM and
frequency-analysis histories are separate.

## Validation

Run with a real renderer; the scope test mutes Master after the PCM tap:

```powershell
$engine = 'D:/Godot Engine/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $engine --path . --script res://tests/oscilloscope_smoke.gd
& $engine --headless --audio-driver WASAPI --path . --script res://tests/loopback_smoke.gd
```

The scope test feeds actual stereo WAV playback through the audio bus. It
checks +1/-1/quadrature correlation, rendered diagonal orientation, a real
quadrature circle, unequal-channel ellipse dimensions, common-gain limiting,
single-channel undefined phase, resource reuse, natural framebuffer decay,
source clearing, bounded quality targets, native detachment, and cleanup.
It saves green/amber Lissajous frames under `.godot/oscilloscope-*.png`.

The extended loopback test verifies that audio from a separate Windows process
reaches StereoPCM as well as the existing FFT, and that changing sources
clears the old phase samples. Existing audio, galaxy, tunnel/city and UI smoke
tests provide regression coverage. Manual acceptance should include your own
music, pause/resume, large resizes and sustained detached/fullscreen playback.

Official references:

- [AudioEffectCapture](https://docs.godotengine.org/en/stable/classes/class_audioeffectcapture.html)
- [ArrayMesh](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html)
- [SubViewport clear/update modes](https://docs.godotengine.org/en/stable/classes/class_subviewport.html)
- [CanvasItem shader blend modes](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html)
