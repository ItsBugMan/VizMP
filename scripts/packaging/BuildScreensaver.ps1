param(
    [string]$Godot = 'D:/Godot Engine/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$stageDirectory = Join-Path $projectRoot 'builds/windows-screensaver'
$helperDirectory = Join-Path $projectRoot 'bin/loopback'
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw 'Godot console executable was not found.' }
if (-not (Test-Path -LiteralPath (Join-Path $helperDirectory 'VizMPLoopback.exe'))) {
    & (Join-Path $projectRoot 'native/build-loopback.ps1')
}
New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
$exportExecutable = Join-Path $stageDirectory 'VizMP.exe'
$screensaverExecutable = Join-Path $stageDirectory 'VizMP.scr'
& $Godot --headless --path $projectRoot --export-release 'Windows Screensaver' $exportExecutable
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exportExecutable)) {
    throw 'Godot export failed. Install matching Godot 4.7.2 export templates and review the export log.'
}
# These are fixed files inside this project's build directory; no recursive moves.
Move-Item -LiteralPath $exportExecutable -Destination $screensaverExecutable -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RunScreensaver.ps1') -Destination (Join-Path $stageDirectory 'RunScreensaver.ps1') -Force
$helperDestination = Join-Path $stageDirectory 'loopback'
New-Item -ItemType Directory -Path $helperDestination -Force | Out-Null
Get-ChildItem -LiteralPath $helperDirectory -File | Where-Object Extension -ne '.pdb' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $helperDestination $_.Name) -Force
}
Write-Output "Built screensaver: $screensaverExecutable"
Write-Output 'Distribute the entire windows-screensaver folder, including exported DLLs and loopback notices.'
Write-Output 'No Windows installation or registry changes were performed.'
