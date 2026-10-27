[CmdletBinding()]
param(
    [string]$Godot = 'D:/Godot Engine/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe',
    [string]$ISCC = '',
    [switch]$SkipHelperBuild,
    [switch]$ExportOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$buildRoot = Join-Path $projectRoot 'builds'
$stage = Join-Path $buildRoot 'windows'
$versionText = Get-Content -LiteralPath (Join-Path $projectRoot 'version.cfg') -Raw
if ($versionText -notmatch '(?m)^version="(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"\s*$') { throw 'version.cfg must contain a stable MAJOR.MINOR.PATCH.' }
$version = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw 'Specify -Godot with the Godot 4.7.2 console executable.' }
$engineVersion = & $Godot --version
if ($engineVersion -notlike '4.7.2.*') { throw "Expected Godot 4.7.2, found $engineVersion" }
if (-not $ExportOnly) {
    if (-not $ISCC) {
        $compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue
        if ($compiler) { $ISCC = $compiler.Source }
        foreach ($candidate in @("${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe", "$env:ProgramFiles/Inno Setup 7/ISCC.exe")) {
            if (-not $ISCC -and (Test-Path -LiteralPath $candidate)) { $ISCC = $candidate }
        }
        if (-not $ISCC) {
            $keys = @('HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/*',
                      'HKLM:/Software/Microsoft/Windows/CurrentVersion/Uninstall/*',
                      'HKLM:/Software/WOW6432Node/Microsoft/Windows/CurrentVersion/Uninstall/*')
            foreach ($entry in (Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object DisplayName -Match '^Inno Setup')) {
                if ($entry.InstallLocation) {
                    $candidate = Join-Path $entry.InstallLocation 'ISCC.exe'
                    if (Test-Path -LiteralPath $candidate) { $ISCC = $candidate; break }
                }
            }
        }
    }
    if (-not (Test-Path -LiteralPath $ISCC -PathType Leaf)) { throw 'Install Inno Setup 6.3+ (or 7), or supply -ISCC. Use -ExportOnly to build the update ZIP only.' }
}
if (-not $SkipHelperBuild) { & (Join-Path $projectRoot 'native/build-loopback.ps1') }
$helper = Join-Path $projectRoot 'bin/loopback'
if (-not (Test-Path -LiteralPath (Join-Path $helper 'VizMPLoopback.exe'))) { throw 'Native helper is missing.' }
# Fixed, validated build target: clear stale export files so removed DLLs cannot ship.
if ([IO.Path]::GetFullPath($stage) -ne (Join-Path $projectRoot 'builds/windows')) { throw 'Unexpected staging path.' }
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
foreach ($export in @(@('Windows Desktop','VizMP.exe'), @('Windows Screensaver','VizMP.scr'))) {
    & $Godot --headless --path $projectRoot --export-release $export[0] (Join-Path $stage $export[1])
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $stage $export[1]))) { throw "Export failed: $($export[0])" }
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'version.cfg') -Destination $stage
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RunScreensaver.ps1') -Destination $stage
Copy-Item -LiteralPath (Join-Path $projectRoot 'skins') -Destination $stage -Recurse
$notices = Join-Path $stage 'licenses/xiph_audio'
New-Item -ItemType Directory -Path $notices -Force | Out-Null
foreach ($notice in @('LICENSE.md', 'THIRD_PARTY_NOTICES.md')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot "addons/xiph_audio/$notice") -Destination $notices
}
$flacLibrary = Join-Path $stage 'libxiph_audio.windows.template_release.x86_64.dll'
if (-not (Test-Path -LiteralPath $flacLibrary -PathType Leaf)) { throw 'FLAC release library is missing from the export.' }
New-Item -ItemType Directory -Path (Join-Path $stage 'loopback') | Out-Null
Get-ChildItem -LiteralPath $helper -File | Where-Object Extension -ne '.pdb' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $stage 'loopback')
}
$archivePath = Join-Path $buildRoot "VizMP_Windows_x64_v$version.zip"
if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $archivePath, [IO.Compression.CompressionLevel]::Optimal, $false)
$artifacts = @($archivePath)
if (-not $ExportOnly) {
    & $ISCC "/DAppVersion=$version" "/DSourceDir=$stage" "/DBuildDir=$buildRoot" (Join-Path $PSScriptRoot 'vizmp_setup.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }
    $artifacts += Join-Path $buildRoot "VizMP_Setup_v$version.exe"
}
$checksums = $artifacts | ForEach-Object { $hash = Get-FileHash -LiteralPath $_ -Algorithm SHA256; "$($hash.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($_))" }
[IO.File]::WriteAllLines((Join-Path $buildRoot 'SHA256SUMS.txt'), $checksums, [Text.Encoding]::ASCII)
$artifacts | Write-Output
