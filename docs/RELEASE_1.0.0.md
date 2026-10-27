# VizMP 1.0.00

First packaged Windows x64 release. The Git tag and updater version are
`v1.0.0` / `1.0.0`.

## Downloads

- **VizMP_Setup_v1.0.0.exe**: Windows installer with optional desktop shortcut
  and screensaver registration.
- **VizMP_Windows_x64_v1.0.0.zip**: portable app and screensaver. Extract the
  complete archive before running `VizMP.exe`; keep the FLAC DLL and helper
  folders beside the app.
- **SHA256SUMS.txt**: SHA-256 checksums for both downloads.

Windows x64, using Godot 4.7.2 Forward+ / D3D12. Installer signing is not
configured for this release.

## Included

- Native FLAC playback alongside MP3, OGG Vorbis and WAV, including external
  files, drag-and-drop, queueing, recursive Media Library scanning and
  screensaver playlists.
- Shared audio routing through the 64-bin FFT analyzer and stereo PCM scope;
  playback position, pause and seeking work with FLAC.
- Dockable and detachable player panels, transport scrubbing, library,
  embedded artwork for supported metadata formats and visualizer fullscreen.
- Radial spectrum, particle galaxy, fractal tunnel, spectrum city and Vector
  CRT scope modes, quality controls and additional skins.
- Desktop audio capture, Windows screensaver integration, installer and
  portable distribution, and an in-app GitHub update flow.

FLAC metadata currently uses the filename as its title; FLAC tags and embedded
cover art are not parsed. See the repository's `docs/FLAC_WINDOWS.md` for
extension setup and `docs/DISTRIBUTION_AND_UPDATES.md` for packaging details.
