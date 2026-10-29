param(
  [string]$Flutter = (Join-Path (Split-Path -Parent $PSScriptRoot) 'flutter-sdk/flutter/bin/flutter.bat'),
  [string]$Dotnet = (Join-Path (Split-Path -Parent $PSScriptRoot) '.dotnet9sdk/dotnet.exe'),
  [switch]$SkipChecks
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
function Check-Exit { if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" } }
if (-not (Test-Path -LiteralPath $Flutter)) { $Flutter = (Get-Command flutter -ErrorAction Stop).Source }
if (-not (Test-Path -LiteralPath $Dotnet)) { $Dotnet = (Get-Command dotnet -ErrorAction Stop).Source }
$version = ((Get-Content pubspec.yaml | Where-Object { $_ -match '^version:' }) -replace '^version:\s*','') -replace '\+.*$',''
$hostVersion = ([xml](Get-Content -Raw native/ControlHost/ControlHost.csproj)).Project.PropertyGroup.Version
if ($version -ne $hostVersion) { throw 'pubspec.yaml and ControlHost.csproj versions must match.' }
& $Flutter pub get; Check-Exit
if (-not $SkipChecks) {
  & $Flutter analyze --no-pub; Check-Exit
  & $Flutter test --no-pub --reporter expanded; Check-Exit
  & $Dotnet run --project native/CoreTests -c Release; Check-Exit
}
& $Dotnet build native/ControlHost/ControlHost.csproj -c Release --nologo; Check-Exit
if (-not $SkipChecks) { & python tool/host_checks.py --dotnet $Dotnet; Check-Exit }
& $PSScriptRoot/tool/export-icons.ps1
& $Flutter build windows --release "--dart-define=APP_VERSION=$version"; Check-Exit
$releaseRoot = Join-Path $PSScriptRoot "dist/$version/win-x64"
New-Item -ItemType Directory -Force $releaseRoot | Out-Null
Copy-Item -Path 'build/windows/x64/runner/Release/*' -Destination $releaseRoot -Recurse -Force
# App-local runtime deployment avoids requiring a machine-wide VC++ installer.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vsPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) { throw 'Visual Studio C++ tools were not found.' }
$redist = Get-Item -Path (Join-Path $vsPath 'VC/Redist/MSVC/*/x64/Microsoft.VC143.CRT') | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $redist) { throw 'Visual C++ redistributable DLLs were not found.' }
Copy-Item -Path (Join-Path $redist.FullName '*.dll') -Destination $releaseRoot -Force
& $Dotnet publish native/ControlHost/ControlHost.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:DebugType=None -o "$releaseRoot/backend"; Check-Exit
Copy-Item -LiteralPath README.md -Destination "$releaseRoot/使用说明.md" -Force
Copy-Item -LiteralPath THIRD_PARTY_NOTICES.md -Destination $releaseRoot -Force
Copy-Item -LiteralPath LICENSE,README.en.md -Destination $releaseRoot -Force
Copy-Item -LiteralPath assets/fonts/LICENSE.txt -Destination "$releaseRoot/HarmonyOS-Sans-LICENSE.txt" -Force
$dotnetRoot = Split-Path -Parent $Dotnet
foreach ($notice in @('LICENSE.txt','ThirdPartyNotices.txt')) {
  if (Test-Path -LiteralPath (Join-Path $dotnetRoot $notice)) { Copy-Item -LiteralPath (Join-Path $dotnetRoot $notice) -Destination "$releaseRoot/backend/$notice" -Force }
}
$checkLog = Join-Path $releaseRoot 'desktop-checks.txt'
if (Test-Path -LiteralPath $checkLog) { Remove-Item -LiteralPath $checkLog }
$app = Start-Process -FilePath "$releaseRoot/go27q32_lite.exe" -ArgumentList '--demo','--self-check' -WindowStyle Hidden -PassThru
if (-not $app.WaitForExit(45000)) { Stop-Process -Id $app.Id; throw 'Desktop self-check timed out (only the test instance was stopped).' }
if ($app.ExitCode -ne 0) { throw "Desktop self-check exited with $($app.ExitCode)." }
if (-not (Test-Path -LiteralPath $checkLog) -or (Get-Content -Raw -LiteralPath $checkLog) -match 'FAIL') { throw 'Desktop self-check failed; inspect desktop-checks.txt.' }
$zip = Join-Path $PSScriptRoot "dist/GO27Q32Lite-$version-windows-x64.zip"
Compress-Archive -Path (Get-ChildItem -LiteralPath $releaseRoot | Where-Object Name -ne 'desktop-checks.txt').FullName -DestinationPath $zip -Force
# A clean source archive, without SDKs, generated caches or other workspace projects.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sourceZip = Join-Path $PSScriptRoot "dist/GO27Q32Lite-$version-source.zip"
if (Test-Path -LiteralPath $sourceZip) { Remove-Item -LiteralPath $sourceZip }
$archive = [System.IO.Compression.ZipFile]::Open($sourceZip,[System.IO.Compression.ZipArchiveMode]::Create)
try {
  $gitRoot = (& git rev-parse --show-toplevel).Replace('/','\').TrimEnd('\')
  if ($gitRoot -ne $PSScriptRoot.TrimEnd('\')) { throw 'Initialize or clone this project as its own Git repository before packaging sources.' }
  $paths = & git -c core.quotepath=false ls-files --cached --others --exclude-standard
  Check-Exit
  foreach ($path in $paths) { [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $PSScriptRoot $path), $path.Replace('\','/'), [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null }
} finally { $archive.Dispose() }
Get-Item -LiteralPath $zip,$sourceZip | Select-Object FullName,Length
