# VizMP architecture blueprint

Priority 1 desktop capture is now implemented. See `DESKTOP_LOOPBACK.md` for
the current file/desktop source routing, PCM API, scene setup and validation.
Priority 2 is implemented in `scenes/visualizers/ParticleGalaxy.tscn`; see
`PARTICLE_GALAXY.md` for lifecycle, shaders, audio events and quality presets.
Priority 3 is implemented in `scripts/ui/`; see `MODULAR_UI_SKINS.md` for
panel composition, native windows, skin/atlas manifests, and persistence.
Raymarched tunnel and MultiMesh city are also implemented. See
`TUNNEL_AND_CITY.md` for scene structure, audio mappings, bounded GPU work,
quality settings, shockwaves and validation.
The vector CRT phase scope is implemented with signed stereo PCM, a static
GPU ribbon, retained HDR phosphor accumulation and CRT post-processing. See
`OSCILLOSCOPE.md` for routing, scene structure, resource ownership and tests.
Windows screensaver dispatch, settings, primary fullscreen and exit guards
are implemented in `scripts/app/ScreensaverManager.gd`; see
`WINDOWS_SCREENSAVER.md` for packaging, preview limitations and validation.
Verified release downloads and Windows distribution are implemented in
`scripts/app/AutoUpdater.gd` and `scripts/packaging/`; see
`DISTRIBUTION_AND_UPDATES.md` for installer, handoff, recovery and CI details.
The future-module descriptions below remain guidance for later expansion.

## Data flow and ownership

```text
Audio source / future playlist
  -> AudioStreamPlayer -> Master effects -> output device
                            |
                     AudioAnalyzer (autoload, after ScreensaverManager)
                        |             |
                 beat_detected    spectrum_updated
                        |             |
                  cameras/UI   VisualizerShaderManager (after StereoPCM)
                                      |
                        global vec4s + 64x1 R8 texture
                                      |
                      CanvasItem and Spatial shader materials
```

Audio processing stays in Godot's audio thread. GDScript queries the engine's
completed FFT on the main thread; it never runs an FFT itself. Analysis queries
64 log bins plus five broad ranges, at most once per rendered frame, capped at
60 Hz. Exponential smoothing uses measured elapsed time. The beat detector
uses positive linear-level derivative, an adaptive baseline, warmup, a silence
gate and refractory period. It is an onset heuristic, not tempo tracking.

Persistent CPU arrays avoid per-bin array creation. The manager packs bins to
64 bytes, updates one existing texture, and writes two vec4 globals per frame.
There is still a small per-update CPU Image upload; profile before moving
analysis to native code. Do not perform RenderingServer global readbacks in
the frame loop. All windows share globals; independent audio sessions would
need per-material parameters instead.

## Uniform contract

- `audio_bands.x`: bass; `.y`: mid; `.z`: treble; `.w`: volume.
- `audio_details.x`: sub-bass; `.y`: highs; `.z`: beat envelope; `.w`: reserved.
- `audio_event.x`: onset serial modulo 65536; `.y`: latest onset strength.
- `audio_spectrum`: 64×1 R8, each texel an 8-bit display level. Sample at
  `vec2((float(bin) + 0.5) / 64.0, 0.5)`. Quantization is intentional for display;
  use R32F or RG32F if future materials need higher precision or stereo bins.

Global declarations live in Project Settings / Shader Globals, serialized in
`project.godot`. They exist before the main scene's materials compile. A global
publisher cannot substitute for these declarations. ShaderMaterial's ordinary
parameters remain appropriate for per-mode palette, speed and intensity.

## Future modules and contracts

`AudioInputService` owns source selection (file player, mic, native desktop
loopback). `PlaylistService` owns accepted file extensions, folder traversal,
queue/shuffle, repeat and transitions. It asks AudioAnalyzer to reset history
on seek or track switch. Use background loading for large media: the starter's
runtime file loaders are synchronous and suitable for initial development.

`StereoCaptureService` owns a separate `AudioEffectCapture` on the chosen bus.
Drain its ring buffer every update, even when no oscilloscope is visible.
Expose a bounded recent `PackedVector2Array` of signed PCM (x=L, y=R), capture
timestamps, overflow counters and optional normalized L/R correlation. Keep
reused display geometry and decimate for the screen resolution. Channel
magnitudes are insufficient to infer stereo phase. Capture must consume at
least the incoming sample rate; process older chunks for correlation before
retaining a recent display window. Do not let an invisible scope fill the buffer.

`VisualizerHost` owns exactly one active mode and a common lifecycle:
`activate(settings)`, `deactivate()`, `apply_settings(settings)`. Modes read
the analyzer/globals rather than owning audio effects. Deactivated modes stop
processing and release GPU-heavy resources. Keep a mode registry of stable
IDs and PackedScene resources; avoid hard-coding mode logic in dock widgets.

`LayoutController` owns HSplitContainer/VSplitContainer dock trees. Dock panels
are independent scenes with stable IDs. Detach by reparenting the panel into a
Window; redock before freeing that Window. Set `gui_embed_subwindows=false`
for native OS windows. Save split offsets, panel IDs and window rectangles to
`user://layout.cfg`, clamping restored rectangles to current monitor bounds.
Windows share rendering globals, so detaching a display needs no new analyzer.

`SkinDefinition` should be a Resource holding a Theme, named textures,
StyleBox resources, palette and optional CanvasItem skin shader. `SkinService`
loads/validates definitions and applies one shared Theme to dock roots and
detached windows. Duplicate resource instances only for intentional overrides.
CRT, glass and metal skin shaders should be bounded effects on panels, with
reduced-motion/flash controls. Do not replace every Control with a unique
material or conflate skins with saved layout state.

`SettingsService` versions and validates `user://settings.cfg` and mode-specific
settings. Use stable IDs so future migrations can preserve layouts and skins.

## Visualizer implementation plan

- Raymarched tunnels/fractals: CanvasItem full-screen pass, bounded ray steps,
  adjustable render scale, time/energy modulation, palette and quality presets.
  Treat mobile/Compatibility support as explicit renderer targets.
- Particle galaxy: GPUParticles3D with shader-driven positions/velocities and
  shared audio globals. Beats update emitter parameters; avoid CPU iteration
  over particles. Clamp emission and brightness independently of signal gain.
- Spectrum city: MultiMeshInstance3D; write static placement and frequency bin
  index once. Read the spectrum texture in the spatial vertex shader for height
  and emission. Give the MultiMesh a conservative custom AABB covering maximum
  shader displacement, or culling will incorrectly remove tall buildings.
- Vector scope: consume signed PCM, not magnitude arrays. Reuse Line2D points
  or a custom strip mesh, with finite persistence passes and a capture overflow
  indicator. Use (L,R) for a Lissajous scope or (L+R,L-R) for a mid/side display.
- Landscape: cache a mesh/noise texture using FastNoiseLite; scroll coordinates
  in the vertex shader, modulate displacement with bounded energy. Avoid
  regenerating a large terrain mesh in GDScript every rendered frame.

## Screensaver and wallpaper boundaries

`ScreensaverManager` parses OS.get_cmdline_args() and OS.get_cmdline_user_args(),
normalizing `/c`, `/c:HWND`, `/s` and `/p HWND`. Entry routes to the normal app,
configuration modal, or isolated saver scene. Preview exits successfully;
native HWND embedding remains unimplemented. See `WINDOWS_SCREENSAVER.md`.

Exit detection has a 0.5-second grace period, an eight-pixel net movement
threshold and a global-position fallback across monitors. Pressed keys/buttons
quit immediately without a fade. The cursor hides after two idle seconds and
is restored on exit. The export preset and staging script produce a tested
Windows `.scr`; actual Windows registration, DPI and idle/resume acceptance
remain manual installation checks.

A borderless fullscreen window is feasible in Godot. A real desktop wallpaper
behind icons requires native Windows WorkerW/desktop integration and lifecycle
handling; a borderless overlay alone is not equivalent. Keep this in a native
adapter with an explicit normal-window fallback. Wallpaper integration is
separate from the implemented screensaver mode.

## Validation strategy

Keep deterministic tests for onset gates plus a real audio-bus smoke test.
For future work, test folder recursion/unsupported media, seek resets, device
changes, pause/resume, window redocking, removed monitors, corrupted settings,
and multi-hour resource growth. GPU mode checks should include pixel cost at
4K, shader compilation, bounded memory and shader-displacement culling.
