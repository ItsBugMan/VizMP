# Raymarched tunnel and spectrum city — Godot 4.7.2

## Run the new modes

Open `project.godot` and press **F5**. In the Visualizer panel, choose
**Fractal tunnel** or **Spectrum city**. Open a file or enable **Live desktop
audio**. Both use the existing AudioAnalyzer and VisualizerShaderManager
without another capture service, FFT, spectrum texture, or shader-global set.

The existing Low / Balanced / High selector configures the active mode.
**Camera motion** freezes tunnel forward flight or city camera movement while
leaving audio-driven color, geometry and shockwaves active. Detaching the
Visualizer panel preserves the same mode instance and its state.

## Mode 1: folded raymarch corridor

Files:

- `shaders/raymarch_tunnel.gdshader`: actual raymarched folded corridor.
- `shaders/tunnel_chromatic.gdshader`: inexpensive chromatic post-process.
- `scripts/visualizers/RaymarchTunnel.gd`: integrated flight and quality limits.
- `scenes/visualizers/RaymarchTunnel.tscn`: independently runnable Control scene.

```text
RaymarchTunnel (Control, full viewport, RaymarchTunnel.gd)
  Tunnel (ColorRect, full rect, raymarch_tunnel.gdshader)
  Chromatic (ColorRect, full rect, tunnel_chromatic.gdshader)
```

This is a raymarched distance-estimator corridor with a curved centerline,
twisted octagonal cross-section, repeated structural ribs and iterative
absolute-value/rotation folds. It is not a pre-rendered texture or a mesh
flying past the camera. The folding is bounded to 2–5 iterations; it is not
an unbounded Mandelbulb volume.

Audio response:

- `audio_details.x` / sub-bass: increases corridor radius (pulse scale).
  GDScript integrates a smoothly approached forward speed of 1–8 units/second
  from `AudioAnalyzer.sub_bass`, the same value published in that global.
  Speed changes do not multiply TIME or teleport the flight position.
- `audio_bands.y` / mid: changes twist and fold rotation; increases requested
  fold depth from 2 to 5, capped by the selected quality budget.
- `audio_bands.z`, `audio_details.y` / treble and highs: color shift and
  radial RGB separation.
- `audio_details.z` / onset envelope: short chromatic spikes and neon shifts.

Chromatic separation uses three taps of the previously rendered tunnel
image via `hint_screen_texture`. It does **not** march three camera rays per
pixel. Godot performs the screen-copy operation inside the tunnel's own
SubViewport; it does not sample the main deck or other panels.

The distance field is warped, so marching uses a conservative 0.42 step
multiplier, a minimum step, a maximum distance of 65 units, early termination,
and a distance-dependent hit epsilon. There is no expensive finite-difference
normal estimate or secondary reflection/shadow ray. Thin detail can alias or
be missed at the lowest ray budget; raise quality for cleaner distant ribs.

All longitudinal geometry/color frequencies repeat after `100 * TAU` units.
The flight position wraps at that period, preserving the infinite-flight
illusion without ever-growing GPU coordinates or TIME rollover artifacts.

Tunnel presets in VisualizerHost:

- **Low:** 48 maximum steps, up to 3 folds, viewport width/height divided by 3.
- **Balanced:** 72 maximum steps, up to 4 folds, width/height divided by 2.
- **High:** 112 maximum steps, up to 5 folds, full panel resolution.

Canvas rendering does not use `scaling_3d_scale`. The host therefore uses
`SubViewportContainer.stretch_shrink` to reduce actual canvas pixel count,
with linear upscaling, and disables unused 3D rendering in this viewport.
High can be much more expensive at fullscreen 4K; Balanced is the starting
preset for an RTX 3070. A standalone **F6** run fills its root viewport; the
host's resolution reduction applies only when running through Main.

## Mode 2: GPU spectrum city

Files:

- `scripts/visualizers/AudioCity.gd`: deterministic grid construction, quality,
  and the bounded transient shockwave pool.
- `scripts/visualizers/CityCamera.gd`: smooth orbital camera and bass approaches.
- `shaders/city_buildings.gdshader`: vertex height and procedural windows.
- `shaders/city_floor.gdshader`: street grid and expanding neon shockwaves.
- `scenes/visualizers/AudioCity.tscn`: independently runnable Node3D scene.

```text
AudioCity (Node3D, AudioCity.gd)
  WorldEnvironment       dark background, ACES tone mapping, glow
  Camera3D               CityCamera.gd, current camera
  Buildings              MultiMeshInstance3D, city_buildings.gdshader
  Floor                  MeshInstance3D / PlaneMesh, city_floor.gdshader
```

All buildings share one BoxMesh and one opaque spatial material through a
single MultiMesh. The CPU constructs transforms on activation or an explicit
quality change. There is no per-building `_process`, mesh rebuilding, transform
upload, or material duplication during music playback.

`use_custom_data` is enabled **before** allocating instances. Each building's
`INSTANCE_CUSTOM` contains:

- `.r`: center coordinate of its assigned spectrum texel, `(bin + 0.5) / 64`.
- `.g`: deterministic height variation.
- `.b`: deterministic cyan/magenta palette and window seed.
- `.a`: reserved, currently 1.

Bins cycle across building indices, covering every one of the 64 bins even
with avenues removed from the grid. The vertex shader reads the existing
64x1 `audio_spectrum` texture using explicit LOD 0. It anchors the cube base
at y=0 and scales its height from that bin's energy and the static seed,
clamped to **28 world units**. Input energy is already smoothed by the shared
AudioAnalyzer; there is no CPU copy of animated heights.

Window cells are generated from face coordinates and building height with
derivative-based edge smoothing. The same spectrum energy controls the
fraction and brightness of illuminated windows. Roofs and facade corners
have neon accents. The unshaded Forward+ material writes HDR radiance directly
to ALBEDO, allowing WorldEnvironment glow without per-window point lights,
transparency, shadow passes or screen-space reflections.

`MultiMesh.custom_aabb` includes the entire grid and the full shader-generated
height. Changing a mesh's vertices in a shader does not automatically update
its CPU culling bounds. Keep AudioCity.MAX_HEIGHT and the shader height clamp
in sync if changing the height range.

City presets:

- **Low:** 24x24 cells, 441 buildings after avenues, 70% 3D render scale.
- **Balanced:** 32x32 cells, 784 buildings, 85% 3D render scale.
- **High:** 48x48 cells, 1,764 buildings, full 3D render scale.

Each cube has 12 triangles. The whole MultiMesh is culled as one object,
which suits this small city viewed from outside. It does not implement
per-building occlusion culling. Quality changes rebuild the static grid
once and resize its floor/camera bounds; they are not intended as per-frame
adaptive switches.

### Floor waves and camera

`AudioCity` listens directly to `AudioAnalyzer.beat_detected(strength)`.
It recycles eight wave slots. Every slot stores origin X/Z, age, and strength
in a `Vector4`. Origins vary near the city center. A new transient replaces
the oldest slot when the pool is full; it cannot grow memory or spawn nodes.

The CPU updates at most eight ages and submits one tiny copied uniform array
when waves are active. Copying makes the last submitted render-server array
independent from the next main-thread mutation. The floor shader expands each
ring at 24 units/second, adds a soft halo, and fades it with age. It caps the
combined radiance of overlapping waves. There are no extra ring meshes,
particles, lights, or duplicated floor passes.

These rings are on the actual grid floor and respect depth occlusion. Dense
maximum-height towers can obscure an inner wave; it reappears across visible
streets and beyond the skyline. Its glow is not an always-visible overlay.

CityCamera orbits slowly and smooths bass/sub-bass into a closer, lower view.
Heavy-bass transients add a brief approach envelope. Its radius/elevation are
bounded relative to grid size, keeping the camera outside the footprint at
maximum approach. It does not apply random shake. Turning Camera motion off
holds its transform exactly; waves and buildings continue reacting.

## Host integration / reuse

`VisualizerHost.gd` now owns four stable mode IDs:

```gdscript
visualizer_host.set_mode(visualizer_host.Mode.RADIAL)  # 0
visualizer_host.set_mode(visualizer_host.Mode.GALAXY)  # 1
visualizer_host.set_mode(visualizer_host.Mode.TUNNEL)  # 2
visualizer_host.set_mode(visualizer_host.Mode.CITY)    # 3
visualizer_host.set_quality(1)                       # Balanced
visualizer_host.set_camera_motion(true)
```

Main.gd adds the two selector entries and follows the host's `mode_changed`
signal, including changes made by scripts. Each non-radial scene implements
`set_quality(index)` and `set_camera_motion(enabled)`. The host preloads scene
resources but instantiates only the selected mode. Switching disables and
frees the old viewport/scene, including city beat listeners and GPU owners.
The city and galaxy use isolated 3D worlds; the tunnel uses a canvas viewport.

To reuse scenes without the host, keep the existing audio autoloads and shader
globals, instance the scene under your own appropriate viewport, and call the
two configuration methods **after** the scene enters the tree. F6 also works
with each `.tscn` directly. No new project shader globals or plugins are needed.

## Validation and tuning

Use the real renderer; headless mode cannot validate GPU output:

```powershell
$engine = 'D:/Godot Engine/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $engine --path . --script res://tests/advanced_modes_smoke.gd
```

The test injects synthetic spectrum/band/transient values inside its own
process, without playing sound. It checks actual rendered image changes,
flight speed/freeze, ray budgets and resolution changes, all 64 building-bin
assignments, conservative height bounds, static instance transforms, visible
floor waves, camera approach/freeze, bounded wave reuse, detached windows,
and cleanup after repeated switches. Preview frames are saved under
`.godot/tunnel-preview.png` and `.godot/city-preview.png`.

It also prints short warmed-up per-viewport GPU timing samples using Godot's
RenderingServer measurements, including viewport dimensions and render scale.
Those samples exclude the other viewports, UI composition and CPU audio work;
they are diagnostics, not whole-application FPS guarantees. First-use shader
compilation and window resolution changes can introduce additional stalls.

Use the existing galaxy, UI, file-audio and desktop-loopback smoke tests for
regression checks. Final acceptance should include your music, quiet passages,
strong bass drops, resizing, detached playback and sustained target-resolution
frame time. A 4K High tunnel costs far more pixels and field evaluations than
the default docked Balanced preview.

Official references:

- [MultiMesh and custom bounds](https://docs.godotengine.org/en/stable/classes/class_multimesh.html)
- [Spatial shader instance data](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)
- [Screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html)
- [RenderingServer timing](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html)
