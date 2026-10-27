# VizMP 1.2.0 — Illustrated Skins & Face Clarity

Eight approved skin redesigns replace the provisional themed artwork: Nocturne,
Redline, Aurora, GT Velocity, Blacksite, Orbital EVA, Sentinel and Xeno Pod.
Detailed original illustrations and ornamental frames surround live playback,
playlist and equalizer controls. Six classic themes remain available.

## Changes

- Denser ASCII Face Rain with overlapping streams and luminance-matched glyphs:
  eyes and facial contours stay readable with quiet or narrow-band music.
- Bounded phosphor brightness prevents washed-out white flashes. Silence still
  produces exactly zero visible RGB pixels.
- Borderless windowed player via **F10** or **Player / visualizer settings**,
  with drag, minimize, maximize/restore, close and resize controls.
- F11/Esc preserves the preceding window size, border preference and visualizer
  visibility. VIS opens a floating visualizer in illustrated skins; closing it
  disables rendering. Library and detachable EQ/playlist remain accessible.
- Automatic migration from known prototype skin selections. Illustrated window
  geometry is stored separately from the classic split layout.
- Updated README, actual player screenshots, asset briefs and validation notes.

## Validation and fidelity

Tested on Godot 4.7.2 Forward+ with an RTX 3070. Layout checks cover 1000×800,
2560×1440 and 3840×2160. Tests cover real playback/EQ, docking, skin changes,
window restoration, exact silence and portrait detail. Controls render at the
window's resolution; the generated source illustrations are 1024×1536 or
1536×1024, not native 4K paintings.

## Download

Choose the Windows x64 installer or extract the complete portable ZIP. Keep the
DLLs, artwork and helper folders together. SHA256SUMS.txt contains checksums.
Existing users can use **Settings / skin → Check for updates…**.

The existing 7.1-device limitation in the file oscilloscope remains; use stereo
output for that mode. The FFT-based visualizers are unaffected by that limitation.
