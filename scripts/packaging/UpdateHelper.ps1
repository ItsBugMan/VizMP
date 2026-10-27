# Windows PowerShell 5.1. All path operations are literal; never evaluates plan content.
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Prepare','Apply')][string]$Action,
      [Parameter(Mandatory)][string]$PlanPath)
$ErrorActionPreference = 'Stop'
$plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
$session = [IO.Path]::GetFullPath($plan.session)
$stage = Join-Path $session 'stage'
$failure = Join-Path $session 'failed.txt'
function Write-Failure([string]$Message) { [IO.File]::WriteAllText($failure, $Message) }
function Assert-NoReparse([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Symbolic links/junctions are not supported in update paths: $cursor"
            }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }; $cursor = $parent
    }
}
function Safe-Child([string]$Root, [string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or $Relative.Contains('\') -or
        $Relative -match '(^/|:|[\x00-\x1f])' -or $Relative.Split('/') -contains '..') { throw "Invalid archive path: $Relative" }
    foreach ($part in $Relative.Split('/')) {
        if ($part -and ($part.EndsWith('.') -or $part.EndsWith(' ') -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\.|$)')) {
            throw "Invalid Windows filename: $Relative"
        }
    }
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $target = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Archive escaped its destination.' }
    Assert-NoReparse $target
    return $target
}
function Encoded([string]$Command) { [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command)) }
function Literal([string]$Value) { "'" + $Value.Replace("'", "''") + "'" }
try {
    Assert-NoReparse $session
    if ([IO.Path]::GetFullPath($PlanPath) -ne (Join-Path $session 'plan.json')) { throw 'Invalid update plan location.' }
    if ($Action -eq 'Prepare') {
        if ((Get-Item -LiteralPath $plan.zip).Length -ne $plan.size) { throw 'Download size does not match the release.' }
        if ((Get-FileHash -LiteralPath $plan.zip -Algorithm SHA256).Hash -ne $plan.sha256) { throw 'SHA-256 verification failed. Download was not installed.' }
        if (Test-Path -LiteralPath $stage) { throw 'Staging directory already exists; download again.' }
        New-Item -ItemType Directory -Path $stage | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($plan.zip)
        try {
            $files = @(); $seen = @{}; [long]$total = 0
            if ($archive.Entries.Count -gt 10000) { throw 'Archive has too many entries.' }
            foreach ($entry in $archive.Entries) {
                $target = Safe-Child $stage $entry.FullName
                if ($seen.ContainsKey($target)) { throw 'Duplicate archive entry.' }; $seen[$target] = $true
                # Unix symlinks and Windows reparse entries must not be extracted.
                if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000 -or ($entry.ExternalAttributes -band 0x400)) { throw 'Archive contains a link.' }
                $total += $entry.Length
                if ($entry.Length -gt 536870912 -or $total -gt 1073741824) { throw 'Archive exceeds update size limits.' }
                if ($entry.FullName.EndsWith('/')) { continue }
                if ($entry.FullName -match '(^|/)(unins.*|apply_update\.bat|UpdateHelper\.ps1|plan\.json)$') { throw 'Archive contains reserved installer/updater files.' }
                $files += $entry.FullName
            }
            foreach ($required in @('VizMP.exe','VizMP.scr','version.cfg','loopback/VizMPLoopback.exe')) {
                if ($files -cnotcontains $required) { throw "Archive missing $required" }
            }
            foreach ($entry in $archive.Entries) {
                if ($entry.FullName.EndsWith('/')) { continue }
                $target = Safe-Child $stage $entry.FullName
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
            }
            $versionText = Get-Content -LiteralPath (Join-Path $stage 'version.cfg') -Raw
            if ($versionText -notmatch ('(?m)^version="' + [regex]::Escape($plan.version) + '"\s*$')) { throw 'Staged version does not match the release tag.' }
            $manifest = @($files | ForEach-Object {
                @{ path = $_; sha256 = (Get-FileHash -LiteralPath (Safe-Child $stage $_) -Algorithm SHA256).Hash }
            })
            [IO.File]::WriteAllText((Join-Path $session 'prepared.json'), (ConvertTo-Json -InputObject $manifest -Depth 4))
        } finally { $archive.Dispose() }
        exit 0
    }
    $install = [IO.Path]::GetFullPath($plan.install)
    Assert-NoReparse $install
    if (-not (Test-Path -LiteralPath (Join-Path $install 'VizMP.exe') -PathType Leaf)) { throw 'Installed VizMP.exe was not found.' }
    # Request elevation BEFORE signalling readiness. On UAC cancellation VizMP stays open.
    $probe = Join-Path $install ('.vizmp-write-' + [guid]::NewGuid().ToString('N'))
    try { [IO.File]::WriteAllText($probe, 'probe'); Remove-Item -LiteralPath $probe }
    catch {
        $identity = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
        if ($identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw }
        $command = '& ' + (Literal $PSCommandPath) + ' -Action Apply -PlanPath ' + (Literal $PlanPath)
        $elevated = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -PassThru -Wait -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',(Encoded $command))
        exit $elevated.ExitCode
    }
    $manifest = Get-Content -LiteralPath (Join-Path $session 'prepared.json') -Raw | ConvertFrom-Json
    foreach ($item in $manifest) {
        $source = Safe-Child $stage $item.path
        $null = Safe-Child $install $item.path
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $item.sha256) { throw 'Staged files changed since verification.' }
    }
    [IO.File]::WriteAllText((Join-Path $session 'ready.txt'), 'ready')
    $running = Get-Process -Id $plan.pid -ErrorAction SilentlyContinue
    if ($running) { $running | Wait-Process -Timeout 120 -ErrorAction Stop }
    # Other saver/app sessions must exit naturally. Never kills unrelated processes.
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        $others = @(Get-Process -Name 'VizMP','VizMPLoopback' -ErrorAction SilentlyContinue | Where-Object {
            try { $_.Path -and $_.Path.StartsWith($install.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) } catch { $false }
        })
        if (-not $others.Count) { break }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($others.Count) { throw 'Another VizMP or screensaver session is still running. Close it and retry.' }
    $backup = Join-Path $session 'backup'
    [IO.Directory]::CreateDirectory($backup) | Out-Null
    $changes = [Collections.Generic.List[object]]::new()
    try {
        foreach ($item in $manifest) {
            $destination = Safe-Child $install $item.path
            $source = Safe-Child $stage $item.path
            $saved = Safe-Child $backup $item.path
            $existed = Test-Path -LiteralPath $destination -PathType Leaf
            if ($existed) {
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($saved)) | Out-Null
                Copy-Item -LiteralPath $destination -Destination $saved
            }
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
            $changes.Add(@{ destination = $destination; backup = $saved; existed = $existed })
            $copied = $false
            for ($attempt = 0; $attempt -lt 20; $attempt++) {
                try { Copy-Item -LiteralPath $source -Destination $destination -Force; $copied = $true; break }
                catch { Start-Sleep -Milliseconds 250 }
            }
            if (-not $copied) { throw "Cannot replace $($item.path)." }
        }
    } catch {
        $copyFailure = $_.Exception.Message
        $rollbackFailures = @()
        for ($index = $changes.Count - 1; $index -ge 0; $index--) {
            $change = $changes[$index]
            try {
                if ($change.existed) { Copy-Item -LiteralPath $change.backup -Destination $change.destination -Force }
                else { Remove-Item -LiteralPath $change.destination -Force -ErrorAction SilentlyContinue }
            } catch { $rollbackFailures += $change.destination }
        }
        throw ($copyFailure + ' Backup retained at ' + $backup + '. Rollback failures: ' + ($rollbackFailures -join ', '))
    }
    [IO.File]::WriteAllText((Join-Path $session 'installed.txt'), $plan.version)
    # Explorer starts the app with the interactive user's token after an elevated update.
    $admin = ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($admin) { (New-Object -ComObject Shell.Application).ShellExecute((Join-Path $install 'VizMP.exe'), '', $install, 'open', 1) }
    else { Start-Process -FilePath (Join-Path $install 'VizMP.exe') -WorkingDirectory $install }
    # Keep backup/logs for recovery. Next downloads use fresh isolated session folders.
    exit 0
} catch {
    Write-Failure $_.Exception.Message
    exit 1
}
