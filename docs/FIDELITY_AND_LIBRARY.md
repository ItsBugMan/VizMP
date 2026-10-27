# VizMP media and rendering overhaul

Implemented against the installed Godot **4.7.2.stable.official.ed1daf0bf**, with actual Forward+/D3D12 execution on the NVIDIA RTX 3070. Existing updater, loopback, EQ, screensaver, and dock ownership remain integrated.

## 1. Audio Library and metadata

- `scripts/ui/LibraryPanel.gd` adds the fifth dockable panel. Add/remove folders, Rescan, Queue all, and double-click a track to play it. Folder roots persist in `user://library.cfg`.
- Recursive traversal advances within a 2.5 ms work budget per frame, retains its directory iterator between frames, deduplicates overlapping roots, and skips links and hidden directories. Individual filesystem calls may exceed the budget on slow/network drives.
- The Tree uses file labels and full path tooltips; the deck and playlist resolve track metadata. Playlist metadata work is spread over frames and does not decode artwork.
- `scripts/audio/AudioMetadata.gd` reads ID3v2.3/v2.4 title/artist/album and APIC PNG/JPEG covers, ID3v1 fallback, Ogg Vorbis comments and METADATA_BLOCK_PICTURE, WAV RIFF INFO, and WAV ID3 chunks. WAV parsing seeks over PCM, including tags after large audio data chunks.
- Reads are bounded: 16 MiB tag/packet input and 8 MiB encoded cover art. Large decoded covers are resized. Unsupported ID3 versions, unsynchronised tags, compressed/encrypted/grouped frames, RF64, and exotic picture encodings fall back gracefully. Embedded cover formats are PNG/JPEG. A missing title falls back to the filename.

## 2. Transport and seeking

`scripts/ui/TransportBar.gd` owns Previous, Play, Pause, Next, the HSlider, and elapsed/duration labels. The Main scene's existing AudioStreamPlayer remains the audio source; the playlist owns queue order. At the end of the queue, playback stops rather than wrapping.

- Dragging previews the destination, then commits a single `seek()` on release. Clicks and keyboard slider changes also seek. Paused tracks remain paused.
- The position display accounts for the last audio mix and output latency while playing. A short seek guard avoids showing an old mixer position immediately after jumping.
- `AudioAnalyzer.reset_after_seek()` replaces only the selected analyzer effect at its original bus index, clears spectrum/transient history, and allows the fresh FFT buffer to settle for 80 ms. `StereoPCM.reset()` clears captured waveform and scope history. EQ and loopback routing retain their owners.
- Desktop loopback disables file transport and seeking, since the application does not control the system audio source.

The timing calculation follows [Godot AudioStreamPlayer documentation](https://docs.godotengine.org/en/latest/classes/class_audiostreamplayer.html).

## 3. Visualizer fullscreen

Use the visualizer's Fullscreen button or **F11**. **Esc**, **F11**, or a left click restores the UI. Keys also route from detached windows.

The existing VisualizerHost is reparented into Main and stretched to the full borderless fullscreen window. The dock layout and previously visible detached windows are hidden. On exit, the original parent, child order, window mode, borderless state, and detached window visibility are restored. The visualizer scene, simulation, audio player, and viewport are retained.

## 4. Skins and layout

Six built-ins are available from Settings / skin. Cyberpunk, Brushed Metal, and Retro Phosphor add distinct colors, typography, SVG nine-slice panel textures, corner accents, button hover/pressed/focus states, themed trees, and progress controls. The original three skins and external JSON atlas skins remain supported.

The split structure is constructed by DockLayout:

```text
Main (Control; SkinManager theme root)
  Player (AudioStreamPlayer)
  DockLayout (MarginContainer)
    HSplitContainer
      VSplitContainer
        Deck slot -> metadata/art + TransportBar
        Equalizer slot
      VSplitContainer
        Visualizer slot -> controls + VisualizerHost
        HSplitContainer
          Playlist slot
          Library slot -> folders + track Tree
```

Each panel can swap slots or detach. Existing four-panel saved orders gain the Library slot automatically. The additional lower split position is persisted. Minimum application size is 1000 x 800 to keep the full control set readable.

## 5. Graphics and quality

- Explicit Forward+ rendering with the existing D3D12 driver. The application requests HDR display output and uses HDR 2D composition; actual HDR output depends on the display and Windows HDR configuration. SDR operation remains supported. HDR render targets do not by themselves guarantee HDR monitor output.
- `VisualizerHost._apply_environment()` centralizes quality: filmic tone mapping; multi-scale glow with threshold 1.1, bloom 0.08, and strength 1.15; balanced/high intensity presets; high-only 4x MSAA; city-only SSAO; high city SSR with 48 steps and depth tolerance 0.25. These effects follow [Godot Environment properties](https://docs.godotengine.org/en/latest/classes/class_environment.html).
- The city uses opaque lit metallic materials, emissive windows/streets, and a directional key light. Depth and normals now contribute to SSAO/SSR. Floor shockwaves have wider, brighter emission so they remain visible through filmic grading. SSR is screen-space and cannot reflect offscreen geometry.
- Galaxy quality budgets are 16,384 / 32,768 / **98,304 GPU particles**. Audio changes density without reallocating the particle pool. Scene environments also receive filmic/glow defaults for direct scene editing.
- The tunnel keeps its bounded 48/72/112 ray steps and 3/4/5 folds. Travel and sample positions explicitly use high precision, and radiance reaches the HDR glow/filmic pass without early Reinhard compression. This uses GPU 32-bit shader math, not double precision.
- The phosphor buffer owns a separate World3D so the outer presentation environment cannot repeatedly grade retained history. The oscilloscope retains its HDR phosphor history and actual stereo PCM geometry; highlights now retain bloom headroom. Source changes and seeks clear phosphor history.
- `shaders/visualizer_grade.gdshader` applies a shared three-sample viewport grade: audio-transient chromatic separation, mild radial lens distortion, vibrance, and vignette. It samples the active viewport texture, keeping UI panels outside the effect. The tunnel retains its own inexpensive chromatic pass as well.
- Low disables environment bloom/SSAO/SSR, Balanced favors moderate resolution and density, High uses full-resolution rendering and the larger effects budgets. SSAO/SSR are not applied to particle sprites or flat canvas modes. Glow is a bloom effect; no costly volumetric fog is implied.

## Verification

Run with the Godot 4.7.2 console executable and this project path:

```powershell
& $godot --headless --path $project --script res://tests/metadata_smoke.gd
& $godot --path $project --script res://tests/overhaul_smoke.gd
& $godot --path $project --script res://tests/ui_smoke.gd
& $godot --path $project --script res://tests/galaxy_smoke.gd
& $godot --path $project --script res://tests/advanced_modes_smoke.gd
& $godot --path $project --audio-driver Dummy --script res://tests/oscilloscope_smoke.gd
```

Tests use dedicated fixtures under `.godot`, disable normal layout persistence, and restore temporary skin selection. Graphics tests verify rendered pixels, audio response, viewport disposal, native window reparenting, and GPU-owned animation. Headless tests cannot validate shader appearance. GPU timings printed by the advanced-mode smoke test measure only its small test viewport; they are not fullscreen performance promises.

### Validation limitation

The oscilloscope suite passes with real Forward+/D3D12 GPU rendering and Godot's Dummy audio driver (which still mixes the generated PCM fixtures through the bus). On this machine the WASAPI run returns zero PCM in the scope fixture and fails its signal assertions, while the separate native FFT audio smoke test passes. The zero-PCM behavior also reproduced using the pre-overhaul Main script; the Windows capture/driver interaction remains unresolved. Native end-to-end oscilloscope capture is therefore not claimed as verified. All other listed integration suites pass on the installed engine/GPU.
