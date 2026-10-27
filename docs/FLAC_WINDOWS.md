# Native FLAC playback — Windows / Godot 4.7.2

Project: `D:/Godot Engine/Apps/VizMP/viz-mp/`. Renderer: Forward+.

## Installed layout

The existing Xiph addon and compiled Windows libraries are reused:

```text
viz-mp/
  addons/xiph_audio/
    xiph_audio.gdextension
    LICENSE.md
    THIRD_PARTY_NOTICES.md
    icons/audio_stream_flac.svg
    bin/
      libxiph_audio.windows.template_debug.x86_64.dll
      libxiph_audio.windows.template_release.x86_64.dll
  scripts/audio/AudioStreamLoader.gd
  tests/flac_smoke.gd
  tests/fixtures/stereo-tones.flac
```

Other platform libraries in the installed addon may remain. The DLLs and
descriptor must come from the same addon build. Windows ARM64 and 32-bit
executables cannot use these x86-64 DLLs.

For a fresh install, get the **compiled** `godot-xiph-audio.zip` release or
Actions artifact from https://github.com/goatchurchprime/godot-xiph-audio.
Extract its `addons/xiph_audio/` into this project's `addons/` directory;
GitHub's source ZIP does not contain the required compiled binaries.
Keep the license and third-party notices when distributing the addon.
Upstream targets Godot 4.5 or newer. This integration was tested locally on
Godot `4.7.2.stable.official.ed1daf0bf` Windows x86-64.

The relevant descriptor settings are:

```ini
[configuration]
entry_symbol = "xiph_audio_library_init"
compatibility_minimum = "4.5"
reloadable = false

[icons]
AudioStreamFLAC = "res://addons/xiph_audio/icons/audio_stream_flac.svg"

[libraries]
windows.debug.x86_64 = "res://addons/xiph_audio/bin/libxiph_audio.windows.template_debug.x86_64.dll"
windows.release.x86_64 = "res://addons/xiph_audio/bin/libxiph_audio.windows.template_release.x86_64.dll"
```

There is no EditorPlugin to enable. Restart the Godot editor after installing
or replacing native binaries. VizMP disables native hot reload to avoid
replacing decoder code during playback. Concurrent editor/export processes
can still collide while copying the Windows `~` DLL; close the other editor
before running editor imports or exports if that error appears. Runtime
tests load successfully with the existing editor open. Do not distribute
generated `~*.dll` copies as dependencies. Forward+ does
not need special audio settings or a different extension build.

## Runtime loading and routing

`AudioStreamLoader.gd` owns the supported extensions and dialog filter.
Main, drag-and-drop, playlist, recursive Media Library scanning and the
screensaver all use this shared policy, including uppercase `.FLAC` paths.

```gdscript
const AUDIO_LOADER = preload("res://scripts/audio/AudioStreamLoader.gd")

func play_path(path: String) -> void:
    var stream: AudioStream = AUDIO_LOADER.load_file(path)
    if stream == null:
        push_warning(AUDIO_LOADER.last_error)
        return
    $Player.stream = stream
    $Player.play()
```

The extension's FLAC API exposes `data` and `is_valid()`, rather than a static
`load_from_file()` method. The shared loader reads the compressed bytes with
`FileAccess`, constructs `AudioStreamFLAC` through `ClassDB`, sets `data`,
then checks `is_valid()`. This works for arbitrary filesystem paths without
editor importing or `ResourceLoader` recognition. Dynamic class lookup lets
the app report a missing extension without breaking MP3/OGG/WAV parsing.
Compressed file bytes reside in memory; decoding is incremental during
playback, without converting the whole track to a WAV buffer.

The existing player stays on Master. Selecting a file switches the existing
AudioLoopbackManager to FILE mode and resets analyzer and stereo history.
Decoded FLAC follows the same route as the built-in audio streams:

```text
AudioStreamFLAC -> AudioStreamPlayer -> Master audio effects -> speakers
                                          |               |
                                    64-bin FFT       stereo PCM tap
                                    AudioAnalyzer       StereoPCM
                                          |               |
                                        visualizer modes
```

No decoder-specific FFT or visualizer changes are required. The integration
test verifies separate 220 Hz left / 1760 Hz right signals through the real
Master FFT and stereo PCM tap, along with pause-preserving seek. Godot mixes
and resamples to its output rate as usual; playback is not a bit-perfect
device bypass. Existing metadata code currently uses filename fallback for
FLAC titles; FLAC tags and embedded artwork are outside this playback change.

## Build from source, if required

Prefer a matching compiled distribution. To rebuild, use a separate source
checkout with pinned recursive submodules, Python/SCons, CMake and the Visual
Studio C++ x64 build tools. From a Developer PowerShell in that checkout:

```powershell
git submodule update --init --recursive
python -m pip install scons
scons build_flac platform=windows target=template_debug arch=x86_64
scons platform=windows target=template_debug arch=x86_64
scons build_flac platform=windows target=template_release arch=x86_64
scons platform=windows target=template_release arch=x86_64
```

These commands follow upstream's current SConstruct. libFLAC is statically
linked. Copy the matching descriptor, libraries, icons and notices together;
reapply `reloadable = false` for this project. Do not change the minimum
compatibility version merely to match the editor's version number.

## Verification and export

```powershell
$godotExe = 'D:/Godot Engine/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
$projectDir = 'D:/Godot Engine/Apps/VizMP/viz-mp'
& $godotExe --headless --path $projectDir --editor --import --quit
& $godotExe --headless --path $projectDir --script res://tests/flac_smoke.gd
& $godotExe --headless --path $projectDir --script res://tests/audio_smoke.gd
```

The FLAC test intentionally feeds malformed bytes once; the native
`AudioStreamFLAC: invalid FLAC data` diagnostic is expected. Success ends in
`Failures: 0`. The test generates external-path copies in user data, then
removes them; the fixture contains generated tones, not a music recording.

Both Windows export presets use x86-64 and all resources. Godot selects the
debug or release DLL from the descriptor and copies it alongside the export;
ship the complete output directory, even when the PCK is embedded in the EXE.
Verify the release DLL is present in that output before packaging, and keep
the addon notices with your distribution. External library tracks do not
need to be bundled in the PCK. In an exported build, open a FLAC, seek, queue
it from the Library and check the spectrum and Vector CRT scope.

Local validation produced `builds/flac-validation/VizMP.exe` and a release
DLL whose SHA-256 matches the installed release DLL. The export command
completed but reported the concurrent-editor `~` DLL copy conflict described
above; repeat with the other editor closed for a clean export log. The
existing broader `overhaul_smoke.gd` checks passed with an ObjectDB leak
warning at teardown; the focused FLAC and audio tests exited cleanly.

If `ClassDB.class_exists("AudioStreamFLAC")` is false, inspect startup errors
for a missing/mismatched DLL or descriptor, confirm x86-64 architecture and
restart the editor after replacing the addon.
