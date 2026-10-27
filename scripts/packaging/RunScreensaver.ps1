param(
    [ValidateSet('Run', 'Configure', 'Preview')][string]$Mode = 'Configure',
    [string]$Screensaver = '',
    [ValidatePattern('^(\d+|0[xX][0-9a-fA-F]+)$')][string]$PreviewHandle = '0'
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Screensaver)) {
    $Screensaver = Join-Path $PSScriptRoot 'VizMP.scr'
    if (-not (Test-Path -LiteralPath $Screensaver)) {
        $Screensaver = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../builds/windows-screensaver/VizMP.scr'))
    }
}
if (-not (Test-Path -LiteralPath $Screensaver -PathType Leaf)) { throw 'Build the screensaver first.' }
# Invoke the PE directly; shell-based .scr associations can intercept arguments.
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = (Resolve-Path -LiteralPath $Screensaver).ProviderPath
$startInfo.UseShellExecute = $false
switch ($Mode) {
    'Run' { $startInfo.Arguments = '/s' }
    'Configure' { $startInfo.Arguments = '/c' }
    'Preview' { $startInfo.Arguments = '/p ' + $PreviewHandle }
}
$launchedProcess = [System.Diagnostics.Process]::Start($startInfo)
Write-Output "Launched VizMP screensaver process $($launchedProcess.Id) in $Mode mode."
