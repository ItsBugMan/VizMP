param([string]$Runtime = 'win-x64')
$ErrorActionPreference = 'Stop'
$projectPath = Join-Path $PSScriptRoot 'LoopbackBridge/LoopbackBridge.csproj'
$outputPath = Join-Path $PSScriptRoot '../bin/loopback'
dotnet publish $projectPath -c Release -r $Runtime --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o $outputPath
if ($LASTEXITCODE -ne 0) { throw 'Loopback helper build failed.' }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'LoopbackBridge/NAudio-LICENSE.txt') -Destination $outputPath
