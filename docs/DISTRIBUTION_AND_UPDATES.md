# Windows distribution and updates

Target: Godot **4.7.2**, Windows x64, Forward+ / D3D12. User settings remain
in `user://`; the installer and ZIP never contain someone's saved settings.

## Build locally

Install matching Godot 4.7.2 export templates, .NET 10 SDK, and
[Inno Setup 6.3+ or 7](https://jrsoftware.org/isdl.php). Commercial use of
Inno Setup is subject to its current licensing terms. From the project folder:

```powershell
./scripts/packaging/build_installer.ps1
```

The script discovers Inno Setup through PATH, standard locations or its Windows
uninstall registry entry, including custom install folders. Use
`-ISCC '<path-to-ISCC.exe>'` to override discovery.
Use `-Godot '<console executable>'` if Godot is elsewhere. The script checks
its version, rebuilds the self-contained WASAPI helper, exports **Windows Desktop**
and **Windows Screensaver**, includes the helper's license notices, skins and
version metadata, then compiles `scripts/packaging/vizmp_setup.iss`.

Outputs for version 1.1.0:

- `builds/VizMP_Setup_v1.1.0.exe` — installer (requires ISCC).
- `builds/VizMP_Windows_x64_v1.1.0.zip` — flat-root portable/update payload.
- `builds/SHA256SUMS.txt` — checksums of generated artifacts.
- `builds/windows/` — complete runnable distribution, including embedded PCKs.

`-ExportOnly` builds the ZIP without Inno Setup. `-SkipHelperBuild` reuses an
already built helper. Outputs are ignored by Git. Default skins/assets are
embedded in each executable; external `skins/` is also included for customization.
Build scripts and development fixtures are excluded from exports, except the
trusted `UpdateHelper.ps1` resource needed by the updater. No .NET runtime needs
to be installed on the destination PC.

## Installer behavior

Default installation is per-user under `{localappdata}/Programs/VizMP`, so
routine updates need no elevation. Choosing **all users** (or `/ALLUSERS`)
uses Program Files and requests administrator access. `/CURRENTUSER` selects
the per-user installation. Start Menu shortcuts are created; desktop shortcut
and screensaver selection are optional. An existing installation should be
updated using the same install scope and destination.

The screensaver task registers `{app}/VizMP.scr` in the current user's
`SCRNSAVE.EXE` value. It avoids copying a second executable into System32,
which would lose the helper folder and drift out of date. It preserves the
previous saver and restores it on uninstall only if VizMP is still selected.
It leaves the user's idle timeout and password/lock policy unchanged. Windows
policy may override saver selection. With alternate administrator credentials,
configure the saver from the intended user's Start Menu shortcut after install.
The shortcut uses `RunScreensaver.ps1` to bypass Windows' `.scr` shell association
and pass `/c` correctly. The existing `/p` graceful fallback is preserved.

Neither builds nor normal updates install anything automatically. The generated
installer is unsigned unless you add Authenticode signing using your own
certificate; SmartScreen reputation is not established by packaging alone.
For signed releases, sign both exports and the native helper before making the
ZIP, and sign the installer after ISCC, then regenerate checksums. Signing keys
must stay in a protected certificate store or CI secret, never in the repository.

## In-app update flow

`AutoUpdater` is registered after the existing audio, skin and screensaver
autoloads. No changes to shaders, audio rendering or visualizer scenes are needed.
Only exported **normal desktop app** launches check automatically; editor,
screensaver, configuration and preview launches stay quiet. In the Main Deck,
**Settings / skin → Check for updates…** opens `UpdateDialog.gd` with status,
download progress, download and restart/install buttons. A status label also
shows available versions on the deck.

The [GitHub latest-release API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)
must be publicly accessible. No GitHub token is embedded in VizMP. Private
repositories need a separate authenticated update service; a 404 can mean
either no release or a private/inaccessible repository. Rate limits and network
failures leave the running app usable. Stable `vMAJOR.MINOR.PATCH` tags are
compared numerically; prereleases and malformed tags are rejected.

Upload **exactly** `VizMP_Windows_x64_v<version>.zip`, not GitHub's source ZIP.
The updater requires the [SHA-256 asset digest supplied by GitHub](https://github.blog/changelog/2025-06-03-releases-now-expose-digests-for-release-assets/),
an HTTPS URL under this repository's release downloads, and a payload no larger
than 512 MiB. Expanded payloads are capped at 1 GiB / 10,000 entries. If an asset
has no digest yet, checking again later is safe. A checksum verifies transport
and release consistency; it is not an independent code-signing signature.

1. `HTTPRequest` streams to `user://updates/new_build.zip`, using its download
   counters for progress. Network work runs in HTTPRequest's worker thread.
2. Windows PowerShell 5.1 verifies size/SHA-256, validates all ZIP paths, rejects
   traversal, alternate streams, links, duplicate entries and reserved filenames,
   and extracts to a unique session folder. Extraction/hashing run in a separate
   process, avoiding long work in Godot's render loop. Required exports, helper
   and `version.cfg` are checked before displaying **Restart and install**.
3. The button writes `user://updates/apply_update.bat`. It waits two seconds,
   then runs the trusted exported `UpdateHelper.ps1` through an encoded command;
   filesystem paths are never interpolated into batch command syntax.
4. The helper checks staging hashes and destination permissions. Program Files
   triggers UAC before readiness is reported. Cancellation leaves VizMP open.
   Once ready, VizMP saves its panel layout and exits. The helper also waits for
   its actual process ID, and for other app/saver/helper sessions to exit.
5. Existing destination files are backed up before replacement; locked writes
   retry, and failures restore previously replaced files. Successful updates
   relaunch `VizMP.exe` with the interactive desktop user's token. The batch
   deletes itself. If policy blocks PowerShell, use the installer instead.

The helper retains `updates/session-*/backup`, `plan.json`, `prepared.json`,
`installed.txt` or `failed.txt` for recovery. Inspect these after a failed restart.
Older sessions can be deleted manually once the update is confirmed. This is a
rollback on replacement failure, not a power-loss-safe filesystem transaction.
Files absent from a future ZIP are retained; releases removing incompatible
runtime files should use a versioned migration or the installer. The installer
owns uninstall metadata; ZIP updates do not refresh its displayed version.

## Automatic GitHub builds

`.github/workflows/release.yml` runs on manual dispatch or `v*` tag pushes. It
fetches Godot and matching templates with verified release-asset digests,
prepares a verified portable Inno compiler on the disposable runner, builds
the helper and both exports, tests the updater and headless screensaver CLI behavior, and uploads
the installer/ZIP/checksums. Manual dispatch creates downloadable build artifacts.
Tag runs additionally publish a stable GitHub Release with those three files;
the tag must exactly match `version.cfg`. Only the publish job can write releases.

For the next patch release, set `version.cfg` to `1.1.1`, commit the implementation,
push that commit and a matching `v1.1.1` tag. Published GitHub assets then become
available to installed clients. A release is built once by CI; clients download
the build rather than rebuilding Godot themselves. Release notes come from the
matching `docs/RELEASE_<version>.md` when present. Do not reuse release tags or silently replace an update
asset; issue a new patch version instead.

## Validation

```powershell
& '<godot-console.exe>' --headless --path . --script res://tests/updater_smoke.gd
./tests/update_helper_smoke.ps1
./tests/screensaver_export_smoke.ps1 -Screensaver "$PWD/builds/windows/VizMP.scr"
```

The helper test stages and applies a tiny compiled fixture inside `.godot/`,
verifies relaunch/backup, rejects bad digests, traversal and staging tampering,
and verifies rollback under a locked destination. It never installs VizMP or
changes screensaver registry values. UAC, Windows installer UI, and signing
require validation on a disposable Windows VM before public distribution.
