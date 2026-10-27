param(
    [string]$Screensaver = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($Screensaver)) { $Screensaver = Join-Path $projectRoot 'builds/windows-screensaver/VizMP.scr' }
if (-not (Test-Path -LiteralPath $Screensaver)) { throw 'Build the screensaver first.' }
$Screensaver = (Resolve-Path -LiteralPath $Screensaver).ProviderPath
$cases = @(
    @{ Name = 'Raw preview HWND'; Args = @('--headless', '/p', '123456'); Marker = 'startup mode PREVIEW' },
    @{ Name = 'Malformed preview'; Args = @('--headless', '/p:0'); Marker = 'exiting preview safely' },
    @{ Name = 'Configuration startup'; Args = @('--headless', '--quit-after', '10', '/c:123456'); Marker = 'startup mode CONFIG' },
    @{ Name = 'Explicit saver'; Args = @('--headless', '--quit-after', '10', '/s'); Marker = 'startup mode SAVER' },
    @{ Name = 'No-argument SCR dispatch'; Args = @('--headless', '--quit-after', '10'); Marker = 'startup mode SAVER' },
    @{ Name = 'Real primary fullscreen'; Args = @('--quit-after', '30', '/s'); Marker = 'fullscreen=true; borderless=true; primary=true' }
)
foreach ($case in $cases) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Screensaver
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $case.Args) { $startInfo.ArgumentList.Add($argument) }
    $probe = [System.Diagnostics.Process]::Start($startInfo)
    if (-not $probe.WaitForExit(10000)) {
        Stop-Process -Id $probe.Id -ErrorAction SilentlyContinue
        throw "Export probe timed out: $($case.Name)"
    }
    $output = $probe.StandardOutput.ReadToEnd() + $probe.StandardError.ReadToEnd()
    if ($probe.ExitCode -ne 0 -or $output -match '(?m)^(SCRIPT ERROR|ERROR):' -or -not $output.Contains($case.Marker)) {
        Write-Output $output
        throw "Export probe failed: $($case.Name), exit $($probe.ExitCode)"
    }
    Write-Output "PASS: $($case.Name)"
}
