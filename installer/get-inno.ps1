$ErrorActionPreference = 'Stop'
$toolsPath = Join-Path $PSScriptRoot '.tools'
$compilerPath = Join-Path $toolsPath 'InnoSetup/ISCC.exe'
if (-not (Test-Path -LiteralPath $compilerPath)) {
  New-Item -ItemType Directory -Path $toolsPath -Force | Out-Null
  $downloadPath = Join-Path $toolsPath 'innosetup-6.7.3.exe'
  Invoke-WebRequest -Uri 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe' -OutFile $downloadPath
  $expectedHash = '9c73c3bae7ed48d44112a0f48e66742c00090bdb5bef71d9d3c056c66e97b732'
  if ((Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Inno Setup download hash mismatch.' }
  $installDir = Join-Path $toolsPath 'InnoSetup'
  $process = Start-Process -FilePath $downloadPath -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/ALLUSERS=0','/NOICONS',('/DIR="' + $installDir + '"')) -WindowStyle Hidden -PassThru -Wait
  if ($process.ExitCode -ne 0) { throw "Inno Setup install failed: $($process.ExitCode)" }
}
if (-not (Test-Path -LiteralPath $compilerPath)) { throw 'ISCC.exe not found.' }
$compilerPath
