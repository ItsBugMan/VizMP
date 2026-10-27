# Priority 2: GPU particle galaxy

## Try it

Open `project.godot` in Godot **4.7.2**, press **F5**, and choose **Particle
galaxy** in the visualizer selector. Open a track or enable **Live desktop
audio**. Both sources use the same audio analyzer and global shader uniforms.

The galaxy has four spiral arms, warm central stars, cyan/violet outer stars,
a procedural glowing core, and an orbiting perspective camera. Bass increases
particle size and motion; sub-bass accelerates the vortex; individual spectrum
bins energize stars at different radii. Detected transients impart a single
outward/vertical velocity kick to every live particle and increase emission
density. The disk then settles toward its resting radii.

Uncheck **Camera motion** to settle the camera into a stationary view. The
visualizer keeps reacting to audio. This control affects camera motion only.

## Scene and files

`scenes/visualizers/ParticleGalaxy.tscn` is independently runnable with **F6**:

```text
ParticleGalaxy (Node3D, ParticleGalaxy.gd)
  WorldEnvironment       dark background, ACES tone mapping, restrained glow
  Camera3D               GalaxyCamera.gd: bounded orbit, onset shake, subtle FOV
  Stars (GPUParticles3D)  custom process shader + procedural billboard quads
  Core (MeshInstance3D)   procedural additive glow, no imported texture
```

The normal Main scene contains a `VisualizerHost` Control with a `Radial`
ColorRect. Selecting galaxy creates a full-size SubViewportContainer, an
isolated SubViewport 3D world, and an instance of ParticleGalaxy. The UI stays
above the visualizer. Returning to radial disables and frees the 3D viewport
and galaxy scene, including particle owners and their resources.

Implementation:

- `scripts/visualizers/VisualizerHost.gd`: active-mode lifecycle, quality and
  camera controls, viewport render scale.
- `scripts/visualizers/ParticleGalaxy.gd`: emission density and beat envelope;
  no iteration over particles on the CPU.
- `scripts/visualizers/GalaxyCamera.gd`: slow orbit and deterministic onset
  motion with a maximum target offset of 0.06 world units per axis by default.
- `shaders/galaxy_process.gdshader`: GPU spawning, vortex velocity, radial
  restoring force, onset impulses, lifetime fade, per-bin color/size response.
- `shaders/galaxy_star.gdshader`: camera-facing additive star quads with a
  procedural core/halo. No lights, shadows, trails, or texture assets.
- `shaders/galaxy_core.gdshader`: camera-facing warm central glow.
- `scripts/visualizers/VisualizerShaderManager.gd`: shared spectrum and band
  publishing plus the new persistent onset event.

For another host, instance the scene under your own 3D viewport. Register the
shader globals and keep the existing autoloads in the same order as this
project. After the scene enters the tree:

```gdscript
galaxy.set_quality(1)          # 0=Low, 1=Balanced, 2=High; reallocates particles.
galaxy.set_camera_motion(true)
```

## Audio contract

The existing globals remain unchanged:

- `audio_bands`: bass, mid, treble, volume, each in [0, 1].
- `audio_details`: sub-bass, highs, decaying onset pulse, reserved.
- `audio_spectrum`: the existing 64x1 R8 display-energy texture.

The new `audio_event` **vec2** is declared in `project.godot`:

- `.x`: integer-valued onset serial, wrapping modulo 65536.
- `.y`: strength of the latest onset.

VisualizerShaderManager increments it on `AudioAnalyzer.beat_detected`. Each
particle stores the last serial it saw in `CUSTOM.w` and applies an impulse
only on a serial change. New particles initialize to the current serial, so
they do not replay a previous beat. This avoids repeatedly applying an impulse
throughout the decaying pulse, and retains an onset that falls between GPU
simulation ticks. Multiple events between two ticks coalesce to the latest
event; the current analyzer's cooldown makes that unlikely at 60 Hz.

`CUSTOM.x` stores normalized age; `.y` birth radius; `.z` appearance seed.
Lifetime fading is independent of the onset envelope. Position integration
is explicit (`disable_velocity`); the shader uses VELOCITY as persistent state
without also letting the engine integrate it a second time.

Emission density is updated on `spectrum_updated` and onset signals from the
same analyzer that supplies the globals. It sets `amount_ratio` and the custom
shader's `spawn_ratio`; custom particle process shaders need their own spawn
rejection. Already emitted particles remain alive as the density changes.
At fixed allocation, effective emission is approximately
`amount * amount_ratio / lifetime`. It is not an instantaneous particle-count
control. Immediate beat bursts come from impulses to the existing stars.

## RTX 3070 starting presets

- **Low**: 16,384 allocated particles, 70% 3D render scale.
- **Balanced** (default): 32,768 particles, 85% 3D render scale.
- **High**: 65,536 particles, full 3D render resolution.

Simulation runs at 60 Hz with particle interpolation. Each star is a two-triangle
quad. The process shader performs one explicit-LOD spectrum lookup per active
particle per simulation tick. No CPU particle transforms or GPU readbacks run
during normal playback. Density changes do not reallocate particle buffers;
changing the explicit quality preset does restart/reallocate the particle
system. Lower amount_ratio does not reduce the allocated particle budget.

The scene prewarms for 3 simulated seconds on activation so it does not start
empty. This is a one-time GPU cost when entering the mode; first use can also
compile shader pipelines. Reduce `Stars.preprocess` for faster entry if needed.
Particle positions are bounded to radius 24 and vertical range [-4, 4]; the
configured AABB includes headroom for their maximum quad scale. Keep those
bounds in sync if you increase radius, burst size, or star size.

This targets the project's **Forward+ / D3D12** renderer. No Compatibility
fallback is implemented. Balanced is a starting preset, not a guaranteed frame
rate at 4K. Measure actual GPU time at your output resolution before raising
particle size, glow, count, or render scale; additive overdraw can dominate.

## Validation

Run with a real GPU renderer (do not add `--headless`):

```powershell
$engine = 'D:/Godot Engine/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $engine --path . --script res://tests/galaxy_smoke.gd
```

The test injects synthetic band/spectrum/beat values into the analyzer only
inside its own process and plays no audio. It checks real GPU-rendered output,
particle bounds, density changes, persistent beat events, camera stabilization,
quality allocations, and resource cleanup after repeated mode switches. It
saves a rendered frame to `.godot/galaxy-preview.png` for visual inspection.
GPU bounds capture and texture readback are test-only diagnostics.

Also run `tests/audio_smoke.gd` and the WASAPI `tests/loopback_smoke.gd` as
described in `DESKTOP_LOOPBACK.md` to verify both input paths. Manually review
the galaxy with music for response, comfort, silence behavior, and sustained
frame time. The automated checks do not establish a frame-rate guarantee.

Godot references:
- https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/particle_shader.html
- https://docs.godotengine.org/en/stable/classes/class_gpuparticles3d.html

Priority 3's modular panels and skin engine are implemented; see
`MODULAR_UI_SKINS.md`. The VisualizerHost now lives inside the Visualizer
panel, and can move into a native window without recreating its galaxy.
