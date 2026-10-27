# Uses a unique .godot fixture; never replaces the real VizMP installation.
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixture = Join-Path $projectRoot ('.godot/update-test-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$helper = Join-Path $projectRoot 'scripts/packaging/UpdateHelper.ps1'
$payload = Join-Path $fixture 'payload'
[IO.Directory]::CreateDirectory((Join-Path $payload 'loopback')) | Out-Null
$compiler = "$env:WINDIR/Microsoft.NET/Framework64/v4.0.30319/csc.exe"
$source = Join-Path $fixture 'Fixture.cs'
[IO.File]::WriteAllText($source, 'using System; using System.IO; class Fixture { static void Main() { File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"relaunched.txt"),"ok"); } }')
& $compiler /nologo /target:winexe "/out:$(Join-Path $payload 'VizMP.exe')" $source
if ($LASTEXITCODE -ne 0) { throw 'Fixture compilation failed.' }
Copy-Item -LiteralPath (Join-Path $payload 'VizMP.exe') -Destination (Join-Path $payload 'VizMP.scr')
[IO.File]::WriteAllText((Join-Path $payload 'version.cfg'), "[application]`nversion=`"1.1.0`"`n")
[IO.File]::WriteAllText((Join-Path $payload 'loopback/VizMPLoopback.exe'), 'fixture helper')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $fixture 'update.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($payload, $zip)
function New-Plan([string]$Name, [string]$Archive = $zip) {
    $session = Join-Path $fixture $Name
    [IO.Directory]::CreateDirectory($session) | Out-Null
    $install = Join-Path $session 'install'
    [IO.Directory]::CreateDirectory($install) | Out-Null
    [IO.File]::WriteAllText((Join-Path $install 'VizMP.exe'), 'old executable')
    $plan = @{ zip=$Archive; size=(Get-Item -LiteralPath $Archive).Length; sha256=(Get-FileHash -LiteralPath $Archive).Hash; version='1.1.0'; install=$install; pid=2147483647; session=$session }
    $path = Join-Path $session 'plan.json'
    [IO.File]::WriteAllText($path, ($plan | ConvertTo-Json))
    return $path
}
function Run-Helper([string]$Plan, [string]$Action, [int]$Expected) {
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper -Action $Action -PlanPath $Plan
    if ($LASTEXITCODE -ne $Expected) {
        $directory = Split-Path -Parent $Plan
        $errorFile = Join-Path $directory 'failed.txt'
        throw "Unexpected $Action result: $(Get-Content -LiteralPath $errorFile -ErrorAction SilentlyContinue)"
    }
}
$good = New-Plan 'good'
Run-Helper $good Prepare 0
Run-Helper $good Apply 0
$goodSession = Split-Path -Parent $good
Start-Sleep -Milliseconds 500
if (-not (Test-Path -LiteralPath (Join-Path $goodSession 'install/relaunched.txt'))) { throw 'Relaunch failed.' }
if ((Get-Content -LiteralPath (Join-Path $goodSession 'backup/VizMP.exe') -Raw) -ne 'old executable') { throw 'Backup failed.' }
Write-Output 'PASS: valid update staged, replaced files, retained backup and relaunched fixture'
$badHash = New-Plan 'bad-hash'
$plan = Get-Content -LiteralPath $badHash -Raw | ConvertFrom-Json
$plan.sha256 = '0' * 64
[IO.File]::WriteAllText($badHash, ($plan | ConvertTo-Json))
Run-Helper $badHash Prepare 1
Write-Output 'PASS: checksum mismatch rejected'
$malicious = Join-Path $fixture 'traversal.zip'
$archive = [IO.Compression.ZipFile]::Open($malicious, [IO.Compression.ZipArchiveMode]::Create)
$entry = $archive.CreateEntry('../escape.exe'); $entry.Open().Dispose(); $archive.Dispose()
Run-Helper (New-Plan 'traversal' $malicious) Prepare 1
if (Test-Path -LiteralPath (Join-Path $fixture 'traversal/escape.exe')) { throw 'ZIP traversal escaped.' }
Write-Output 'PASS: ZIP traversal rejected'
$changed = New-Plan 'changed-stage'
Run-Helper $changed Prepare 0
[IO.File]::WriteAllText((Join-Path (Split-Path -Parent $changed) 'stage/VizMP.exe'), 'tampered')
Run-Helper $changed Apply 1
Write-Output 'PASS: staging tampering rejected before handoff'
$rollback = New-Plan 'rollback'
Run-Helper $rollback Prepare 0
$rollbackSession = Split-Path -Parent $rollback
$items = @(Get-Content -LiteralPath (Join-Path $rollbackSession 'prepared.json') -Raw | ConvertFrom-Json)
$lockedPath = Join-Path $rollbackSession ('install/' + $items[-1].path)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($lockedPath)) | Out-Null
[IO.File]::WriteAllText($lockedPath, 'locked old file')
$lock = [IO.File]::Open($lockedPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try { Run-Helper $rollback Apply 1 } finally { $lock.Dispose() }
if ((Get-Content -LiteralPath (Join-Path $rollbackSession 'install/VizMP.exe') -Raw) -ne 'old executable') { throw 'Rollback did not restore original executable.' }
Write-Output 'PASS: locked destination triggers rollback of previously replaced executable'
Write-Output "Fixture logs retained: $fixture"
