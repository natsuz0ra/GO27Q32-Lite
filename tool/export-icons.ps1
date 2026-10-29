$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Drawing
$source = [System.Drawing.Image]::FromFile((Join-Path $projectRoot 'assets/icons/go27q32.png'))
$iconStream = [System.IO.MemoryStream]::new()
$writer = [System.IO.BinaryWriter]::new($iconStream)
$sizes = @(16,20,24,32,40,48,64,128,256)
$writer.Write([UInt16]0); $writer.Write([UInt16]1); $writer.Write([UInt16]$sizes.Count)
$pngFrames = [System.Collections.Generic.List[byte[]]]::new()
try {
  foreach ($size in $sizes) {
    $bitmap = [System.Drawing.Bitmap]::new($size,$size,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($source,0,0,$size,$size)
    $stream = [System.IO.MemoryStream]::new()
    $bitmap.Save($stream,[System.Drawing.Imaging.ImageFormat]::Png)
    $pngFrames.Add($stream.ToArray())
    $bitmap.Save((Join-Path $projectRoot "assets/icons/go27q32-$size.png"),[System.Drawing.Imaging.ImageFormat]::Png)
    $stream.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
  }
  $offset = 6 + 16 * $sizes.Count
  for ($i=0; $i -lt $sizes.Count; $i++) {
    $dimension = if($sizes[$i] -eq 256){0}else{$sizes[$i]}
    $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
    $writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([UInt16]1); $writer.Write([UInt16]32)
    $writer.Write([UInt32]$pngFrames[$i].Length); $writer.Write([UInt32]$offset)
    $offset += $pngFrames[$i].Length
  }
  foreach ($frame in $pngFrames) { $writer.Write($frame) }
  [System.IO.File]::WriteAllBytes((Join-Path $projectRoot 'windows/runner/resources/app_icon.ico'),$iconStream.ToArray())
  Write-Output 'Exported nine alpha-preserving icon sizes (16–256 px) and Windows ICO.'
} finally { $writer.Dispose(); $iconStream.Dispose(); $source.Dispose() }
