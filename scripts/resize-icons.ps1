# Resizes snap/gui/icon.png to the sizes required for MSIX packaging.
# Output is written to packaging/Assets/ (must already exist).

Add-Type -AssemblyName System.Drawing
$sourceIcon = [System.Drawing.Image]::FromFile("snap/gui/icon.png")

foreach ($size in @(44, 48, 150, 256)) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.DrawImage($sourceIcon, 0, 0, $size, $size)
    $g.Dispose()
    $bmp.Save("packaging/Assets/icon${size}x${size}.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

$bmp = New-Object System.Drawing.Bitmap 50, 50
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.DrawImage($sourceIcon, 0, 0, 50, 50)
$g.Dispose()
$bmp.Save("packaging/Assets/StoreLogo.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

$sourceIcon.Dispose()

