# Native Windows screensaver — Godot 4.7.2

## Ready-to-test build

The release build is staged at:

```text
builds/windows-screensaver/
  VizMP.scr                Godot Windows x64 executable, embedded PCK
  RunScreensaver.ps1       direct native launcher; no installation changes
  loopback/
    VizMPLoopback.exe      self-contained WASAPI helper
    NAudio-LICENSE.txt
    LICENSE.TXT
    THIRD-PARTY-NOTICES.TXT
```

Keep the entire directory together. If a future Godot export produces
additional DLLs, preserve those beside the executable as well. No Windows
installation, registry update, existing screensaver selection, or System32
copy has been performed by the build/test workflow.

From the project directory:

```powershell
./scripts/packaging/RunScreensaver.ps1 -Mode Configure
./scripts/packaging/RunScreensaver.ps1 -Mode Run
./scripts/packaging/RunScreensaver.ps1 -Mode Preview -PreviewHandle 123456
```

The same launcher is copied into the staged folder, where it can be run as
`./RunScreensaver.ps1 -Mode Configure` after moving that folder elsewhere.
It calls the executable directly with `UseShellExecute=false`. This matters
because shell-based `.scr` file associations can intercept arguments passed
through a simple PowerShell invocation or Start-Process. The packaged launcher
also works with Windows PowerShell 5.1; the automated export test uses
PowerShell 7's ProcessStartInfo.ArgumentList API.

## Startup commands

- **`/s`**, case-insensitive: visualizer-only screensaver, borderless fullscreen
  on the primary monitor, saved mode/quality/skin/audio preferences.
- **No application arguments:** a `.scr` executable starts the saver. The
  supplied dedicated export preset also sets `windows_screensaver`, so its
  temporary `.exe` build has the same default. A normal desktop `.exe` without
  that custom feature, and an editor F5 run, keep the regular modular app.
- **`/c`**, **`/c:HWND`**, or **`/c HWND`**: opens the configuration modal.
  Save or Cancel closes this configuration process. Main Deck also offers
  **Settings / skin -> Screensaver settings…**, which leaves the app open.
- **`/p HWND`** or **`/p:HWND`**: exits successfully without loading a
  visualizer, opening audio capture, or creating a fullscreen window.
  Malformed/missing/zero handles follow the same safe preview exit.
- Conflicting `/s` and `/c`, or unknown screensaver-only arguments, exit with
  code 2. Any recognized `/p` takes precedence to prevent an accidental
  fullscreen preview. Repeated identical flags are harmless.

Both `OS.get_cmdline_args()` and `OS.get_cmdline_user_args()` are inspected.
Direct Windows slash flags were tested with the installed engine and export.
For development, Godot's `--` delimiter avoids engine-option collisions:

```powershell
$engine = 'D:/Godot Engine/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $engine --path . -- /c
& $engine --path . -- /s
& $engine --path . -- /p 123456
```

HWND text is validated and retained without floating-point conversion, but
**native HWND embedding is not implemented**. Godot's renderer/window parent
must not be changed through an invented GDScript handle binding. Windows'
small thumbnail therefore stays blank; its full-screen **Preview** button
uses `/s` and runs the actual saver. `/c`'s owner handle is also not used for
cross-process parenting; the modal belongs to VizMP's own root window.

Standalone `/c` uses one native app window with an embedded settings modal.
Opening settings from the regular app preserves its existing native-subwindow
configuration for dockable panels.

Godot does not allow hiding its main Window. Preview startup minimizes that
window before exiting, and never constructs the Main or Screensaver scenes.
The engine still initializes; zero process/window startup latency is not
claimed for the blank-thumbnail fallback.

## Saved configuration

Preferences are versioned and stored in **`user://screensaver_config.cfg`**.
With the current project name and normal Windows user-data settings, this is:

```text
%APPDATA%\Godot\app_userdata\VizMP\screensaver_config.cfg
```

Fields include default visualizer ID (0 Radial, 1 Galaxy, 2 Tunnel, 3 City,
4 Scope), quality, skin manifest path, audio source, playlist directory,
recursive scan, playlist volume and scope phosphor color. Defaults are
Galaxy, Balanced, Classic Mint, desktop loopback, and -12 dB for playlist
playback. Desktop capture is not replayed through the speakers.

The configuration modal previews skins without modifying the regular app's
saved skin setting. Cancel restores the previous skin and leaves saver
preferences untouched. Save validates the selected skin and, for playlist
mode, an existing absolute directory. It writes a temporary file then replaces
the previous configuration. Save failures stay visible in the modal. Missing,
unknown-version or malformed preferences fall back to validated defaults.

## Input handling and exit

ScreensaverManager owns one guard, active only during a saver session:

1. A **0.5-second startup grace** ignores initial pointer positioning and the
   activation key. Normal app/configuration input is never treated as an exit.
2. `InputEventMouseMotion.relative` accumulates net displacement. At **8 logical
   pixels**, the guard calls `get_tree().quit()` immediately. Alternating sensor
   jitter cancels rather than accumulating path length.
3. Any pressed keyboard key, mouse button/wheel or touchscreen press exits
   after grace. Key releases do not exit. There is no fade or blocking dialog.
4. Global mouse position is also checked while the real saver is active, so
   movement onto a secondary monitor is detected outside the primary window.
5. The cursor hides after **two seconds without movement**. Sub-threshold motion
   resets the idle timer and reveals it. Exit restores the previous mouse mode.

The primary monitor uses normal borderless fullscreen rather than an exclusive
display-mode change. The saver caps rendering at 60 FPS (or preserves a lower
existing limit) and restores the prior cap on exit. Only one visualizer is
active; no dock tree, saved detached windows, playlist UI or file dialogs are
constructed in the screensaver scene. Existing audio/PCM autoloads are reused.
Normal shutdown releases the native loopback helper and GPU scene resources.

This visual mode does not implement session locking or credential handling.
Windows owns **On resume, display logon screen** and related policies. Validate
that setting through a real Windows-initiated idle/resume cycle before relying
on the installed saver in your environment. Launching the test wrapper is not
equivalent to a Windows-managed lock/resume session.

## Playlist behavior

Playlist mode scans MP3, OGG and WAV files, optionally including subfolders,
and shuffles the queue. It reshuffles on each pass, avoiding a direct repeat
at the cycle boundary when multiple valid tracks are available. Directory
links/reparse points are skipped to avoid recursive cycles. The scan yields
to the scene tree after approximately 3 ms of work and caps results at 10,000
tracks / 2,000 directories, keeping input responsive during discovery.

Missing/removed/undecodable tracks are skipped with a frame yield rather than
a tight retry loop. If no files can play, the selected visualizer remains idle
and a short status message disappears after six seconds. If the loopback helper
cannot start, the saver tries the saved playlist directory. A temporarily
unavailable Windows audio endpoint remains in the loopback manager's normal
recovery mode instead of unexpectedly starting playlist sound.

Playback uses the project's existing external-file loaders, not a new
streaming decoder. Very large files can briefly stall during loading; compressed
music is preferable to huge WAV files for screensaver playlists. Actual input
shutdown happens as soon as the engine dispatches the event.

## Export from Godot

Matching **Godot 4.7.2 Windows export templates** are required. They were
available on this machine and the export succeeded.

The provided `export_presets.cfg` contains **Windows Screensaver**:

- Windows Desktop, x86_64, Forward+ / the project's D3D12 configuration.
- Custom feature `windows_screensaver`.
- **Embed PCK enabled**, so renaming the executable does not separate it from
  its resources or depend on a particular `.pck` filename.
- Native console wrapper disabled.
- `skins/*.json` included as non-resource files.
- Add explicit include filters for any additional custom skin JSON files
  outside that directory; external user skins must remain at their saved paths.
- Tests, docs, native build sources and generated build folders excluded.

Build from the project directory:

```powershell
./scripts/packaging/BuildScreensaver.ps1
```

The script exports `VizMP.exe`, renames it to `VizMP.scr`, copies the direct
launcher, and stages the self-contained loopback helper plus notices. If the
helper has not been built, it invokes `native/build-loopback.ps1`; that first
build needs the .NET 10 SDK. End users do not need .NET or Godot installed.

Equivalent editor steps:

1. Project -> Export -> select **Windows Screensaver** (or create the matching
   Windows Desktop preset).
2. Confirm x86_64, Embed PCK, skins JSON inclusion and console-wrapper settings.
3. Export Release to a new stable folder as `VizMP.exe`.
4. Rename **only the extension** to `VizMP.scr`. Enable filename extensions in
   Explorer so it does not become `VizMP.scr.exe`.
5. Copy the `bin/loopback` folder beside the `.scr`, and retain all other files
   generated by the Windows exporter. Include dependency license notices.

For a separate regular desktop-app export, use another Windows preset without
the `windows_screensaver` custom feature. The `.scr` suffix itself still enables
the no-argument screensaver behavior.

## Select it in Windows

First place the **entire staged folder** in a stable location. Right-click
`VizMP.scr` -> **Install** (possibly under **Show more options**) to open Screen
Saver Settings. Alternatively, run the documented Windows Control Panel entry:

```powershell
rundll32.exe desk.cpl,InstallScreenSaver "C:\Apps\VizMP\VizMP.scr"
```

Replace the example path with your stable `.scr` location. This command changes
your Windows screensaver selection; it is supplied for you to run, and was not
executed during development. Configure via **Settings**, test via **Preview**,
choose the idle timeout, and apply your desired resume/logon setting. Leave the
folder in place because the selection references that executable path.

If you specifically want system-directory discovery, an administrator can place
the `.scr` and all required sibling dependencies in **`%WINDIR%\System32`** on
64-bit Windows. Keep the relative `loopback` directory beside it. Do not copy
only the `.scr` when desktop capture is required, and do not overwrite existing
system/runtime files or an unrelated `loopback` directory. Installing a complete
folder in a stable app location and selecting its full path is easier to update
and avoids mixing app files with Windows components. No system-directory copy
or elevation is performed by the provided scripts.

## Implementation files

- `scripts/app/ScreensaverManager.gd`: argument parser, atomic settings,
  primary-screen setup, cursor timing and exit guards.
- `scripts/app/Entry.gd`, `scenes/Entry.tscn`: initial dispatch before app UI.
- `scripts/app/Screensaver.gd`, `scenes/Screensaver.tscn`: isolated visualizer,
  audio startup and cooperative shuffled playlist.
- `scripts/app/ScreensaverConfigDialog.gd`: shared native configuration modal.
- `scripts/app/Main.gd`: adds the screensaver settings menu entry.
- `export_presets.cfg`, `scripts/packaging/*.ps1`: reproducible Windows package.

ScreensaverManager is first in Autoload so preview/config intent is known
before scene dispatch. AudioAnalyzer, AudioLoopbackManager, StereoPCM,
VisualizerShaderManager and SkinManager retain their relative order.

## Validation and remaining acceptance

```powershell
$engine = 'D:/Godot Engine/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $engine --path . --script res://tests/screensaver_smoke.gd
& $engine --headless --path . --script res://tests/screensaver_exit_probe.gd
./tests/screensaver_export_smoke.ps1
```

The screensaver smoke checks parser variants/preview safety, preferences and
atomic overwrite on Windows, startup grace, jitter tolerance, key handling,
cursor idle timing, modal Save/Cancel including Escape, recursive discovery,
actual WAV playback, isolated scene construction and cleanup. It writes only
`.godot` test fixtures and restores user preferences. The isolated exit probe
checks the real `_input` -> SceneTree.quit path.

The export suite launches the actual `.scr` with direct native process creation.
It checks preview success, configuration startup, explicit `/s`, no-argument
dispatch and real primary-monitor borderless fullscreen. Time-bounded tests
exit automatically. The full existing audio/visual/UI suites are also retained.

Native Windows screenshot capture through the desktop automation helper timed
out for the exported configuration window during development; an internally
rendered modal preview and direct dialog-input tests were used for UI QA.
Real desktop key injection also confirmed Escape dismissal of the exported
settings window and Space-key shutdown of the fullscreen `.scr`, followed by
saver/helper process cleanup. Manual acceptance still includes actual Control
Panel selection, thumbnail fallback, other input devices, cursor behavior
across monitors/DPI, sustained audio
playback and a Windows-managed idle/resume/logon cycle. No registration or
security settings were changed as part of testing.

Official references:

- [Microsoft screensaver command-line sample](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms686421(v=vs.85))
- [Windows screensaver registration entry and InstallScreenSaver](https://learn.microsoft.com/en-us/windows/win32/devnotes/scrnsave-exe)
- [Windows screensaver library conventions](https://learn.microsoft.com/en-us/windows/win32/lwef/screen-saver-library)
- [Godot Windows exports and PCK embedding](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html)
- [Godot command-line arguments](https://docs.godotengine.org/en/stable/classes/class_os.html)
