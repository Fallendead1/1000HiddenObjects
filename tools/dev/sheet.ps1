param([string]$Dir, [string]$Out, [string[]]$Names, [int]$Cols = 5, [int]$Cell = 320)
# Tiles PNGs (by base name) into one labelled contact sheet.
Add-Type -AssemblyName System.Drawing
$rows = [math]::Ceiling($Names.Count / $Cols)
$bmp = New-Object System.Drawing.Bitmap ($Cols * $Cell), ($rows * $Cell)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = 'HighQualityBicubic'
$g.Clear([System.Drawing.Color]::FromArgb(40, 44, 60))
$font = New-Object System.Drawing.Font 'Arial', 11, ([System.Drawing.FontStyle]::Bold)
for ($i = 0; $i -lt $Names.Count; $i++) {
	$p = Join-Path $Dir ($Names[$i] + '.png')
	if (Test-Path $p) {
		$img = [System.Drawing.Image]::FromFile($p)
		$x = ($i % $Cols) * $Cell; $y = [math]::Floor($i / $Cols) * $Cell
		$h = [int]($Cell * $img.Height / $img.Width)
		$g.DrawImage($img, $x, $y, $Cell, [math]::Min($h, $Cell))
		$g.DrawString($Names[$i], $font, [System.Drawing.Brushes]::White, $x + 6, $y + 6)
		$img.Dispose()
	}
}
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"saved $Out"
