param([string]$Iscc = '', [string]$Version = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceVersion = ((Get-Content (Join-Path $projectRoot 'pubspec.yaml') | Where-Object { $_ -match '^version:' }) -replace '^version:\s*','') -replace '\+.*$',''
if (-not $Version) { $Version = $sourceVersion }
if ($Version -ne $sourceVersion -or $Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Installer version must match pubspec.yaml.' }
if (-not $Iscc) { $Iscc = & (Join-Path $PSScriptRoot 'get-inno.ps1') }
$payload = Join-Path $projectRoot "dist/$Version/win-x64"
if (-not (Test-Path -LiteralPath "$payload/backend/GO27Q32.ControlHost.exe")) { throw 'Build the complete Windows payload first.' }
$binaryVersion = (Get-Item -LiteralPath "$payload/go27q32_lite.exe").VersionInfo.ProductVersion -replace '\+.*$',''
if ($binaryVersion -ne $Version) { throw "Payload version mismatch: $binaryVersion" }
& $Iscc "/DAppVersion=$Version" "/DPayloadDir=$payload" "/DOutputDir=$(Join-Path $projectRoot 'dist')" (Join-Path $PSScriptRoot 'GO27Q32Lite.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }
$setup = Join-Path $projectRoot "dist/GO27Q32Lite-$Version-windows-x64-setup.exe"
$artifacts = @($setup, (Join-Path $projectRoot "dist/GO27Q32Lite-$Version-windows-x64.zip"), (Join-Path $projectRoot "dist/GO27Q32Lite-$Version-source.zip"))
$lines = foreach ($file in $artifacts) {
  if (-not (Test-Path -LiteralPath $file)) { throw "Release file missing: $file" }
  (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + (Split-Path -Leaf $file)
}
$lines | Set-Content -LiteralPath (Join-Path $projectRoot 'dist/SHA256SUMS.txt') -Encoding utf8NoBOM
Get-Item -LiteralPath $setup | Select-Object FullName,Length
