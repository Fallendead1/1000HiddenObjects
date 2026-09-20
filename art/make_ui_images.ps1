param([string]$OutDir)
# Draws the UI images that are easier to generate than to model:
#   Spin_Wheel.png   the daily spin's face: 10 slices, the first centred at the top, clockwise,
#                    in the order of RetentionConfig.Spin
#   Glow_Soft.png    a soft round glow (white, tinted in game)
#   Rays_Soft.png    soft light rays fading out from the middle (white, tinted in game)
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $OutDir | Out-Null
function C($r, $g, $b, $a = 255) { [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }

# ---------------- the wheel ----------------
$size = 1024; $c = $size / 2
$bmp = New-Object System.Drawing.Bitmap $size, $size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.Clear([System.Drawing.Color]::Transparent)
# slice colours: (light inner, deep outer) in RetentionConfig.Spin order
$slices = @(
	@((C 190 255 120), (C 60 190 20)),    # $50        cash green
	@((C 120 225 255), (C 0 130 235)),    # XP         cyan
	@((C 120 240 140), (C 10 150 60)),    # $100       green
	@((C 225 140 255), (C 140 20 220)),   # Quick Hint purple
	@((C 255 250 225), (C 235 200 130)),  # Mop Pup    cream
	@((C 255 200 90),  (C 240 120 0)),    # $250       orange
	@((C 255 140 200), (C 235 20 120)),   # 2X Cash    pink
	@((C 255 140 140), (C 225 30 50)),    # Super Hint red
	@((C 255 240 130), (C 245 170 0)),    # $1,000     gold
	@((C 90 60 150),   (C 25 12 60))      # Dragon     royal night
)
$n = $slices.Count; $step = 360.0 / $n
$rOuter = 470; $rect = New-Object System.Drawing.RectangleF ($c - $rOuter), ($c - $rOuter), ($rOuter * 2), ($rOuter * 2)
for ($i = 0; $i -lt $n; $i++) {
	$start = -90 - $step / 2 + $i * $step
	$path = New-Object System.Drawing.Drawing2D.GraphicsPath
	$path.AddPie($rect.X, $rect.Y, $rect.Width, $rect.Height, $start, $step)
	$brush = New-Object System.Drawing.Drawing2D.PathGradientBrush $path
	$brush.CenterPoint = New-Object System.Drawing.PointF $c, $c
	$brush.CenterColor = $slices[$i][0]
	$brush.SurroundColors = @($slices[$i][1])
	$brush.FocusScales = New-Object System.Drawing.PointF 0.25, 0.25
	$g.FillPath($brush, $path)
	$brush.Dispose(); $path.Dispose()
}
# stars on the dragon's night slice
$rnd = New-Object System.Random 7
$mid = (-90 + 9 * $step) * [math]::PI / 180
for ($k = 0; $k -lt 26; $k++) {
	$a = $mid + ($rnd.NextDouble() - 0.5) * ($step * [math]::PI / 180) * 0.8
	$r = 150 + $rnd.NextDouble() * 300
	$s = 3 + $rnd.NextDouble() * 5
	$b = New-Object System.Drawing.SolidBrush (C 255 230 140 (120 + $rnd.Next(120)))
	$g.FillEllipse($b, [float]($c + [math]::Cos($a) * $r - $s / 2), [float]($c + [math]::Sin($a) * $r - $s / 2), [float]$s, [float]$s)
	$b.Dispose()
}
# dividers
$pen = New-Object System.Drawing.Pen (C 255 255 255 235), 7
for ($i = 0; $i -lt $n; $i++) {
	$a = (-90 - $step / 2 + $i * $step) * [math]::PI / 180
	$g.DrawLine($pen, [float]$c, [float]$c, [float]($c + [math]::Cos($a) * $rOuter), [float]($c + [math]::Sin($a) * $rOuter))
}
# a soft shine over the top half
$shine = New-Object System.Drawing.Drawing2D.GraphicsPath
$shine.AddEllipse(($c - $rOuter), ($c - $rOuter), ($rOuter * 2), ($rOuter * 2))
$g.SetClip($shine)
$sb = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Point 0, 0), (New-Object System.Drawing.Point 0, $size), (C 255 255 255 70), (C 0 0 0 60)
$g.FillRectangle($sb, 0, 0, $size, $size)
$g.ResetClip()
# the rim: dark ring, gold ring, bulbs
$g.DrawEllipse((New-Object System.Drawing.Pen (C 60 30 10), 60), ($c - $rOuter - 12), ($c - $rOuter - 12), (($rOuter + 12) * 2), (($rOuter + 12) * 2))
$rimBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Point 0, 0), (New-Object System.Drawing.Point $size, $size), (C 255 236 140), (C 225 140 0)
$g.DrawEllipse((New-Object System.Drawing.Pen $rimBrush, 40), ($c - $rOuter - 12), ($c - $rOuter - 12), (($rOuter + 12) * 2), (($rOuter + 12) * 2))
for ($k = 0; $k -lt 20; $k++) {
	$a = ($k * 18 - 90 + 9) * [math]::PI / 180
	$x = $c + [math]::Cos($a) * ($rOuter + 12); $y = $c + [math]::Sin($a) * ($rOuter + 12)
	$g.FillEllipse((New-Object System.Drawing.SolidBrush (C 255 255 255 90)), [float]($x - 17), [float]($y - 17), 34, 34)
	$g.FillEllipse((New-Object System.Drawing.SolidBrush (C 255 252 225)), [float]($x - 11), [float]($y - 11), 22, 22)
}
$bmp.Save((Join-Path $OutDir 'Spin_Wheel.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

# ---------------- soft glow ----------------
$size = 512; $c = $size / 2
$bmp = New-Object System.Drawing.Bitmap $size, $size
for ($y = 0; $y -lt $size; $y++) {
	for ($x = 0; $x -lt $size; $x++) {
		$d = [math]::Sqrt(($x - $c) * ($x - $c) + ($y - $c) * ($y - $c)) / $c
		$a = if ($d -ge 1) { 0 } else { [math]::Pow(1 - $d, 2.2) }
		$bmp.SetPixel($x, $y, (C 255 255 255 ([int](255 * $a))))
	}
}
$bmp.Save((Join-Path $OutDir 'Glow_Soft.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

# ---------------- soft rays ----------------
$size = 768; $c = $size / 2
$bmp = New-Object System.Drawing.Bitmap $size, $size
$rnd = New-Object System.Random 11
$rays = @()
for ($k = 0; $k -lt 18; $k++) { $rays += ,@(($k * 20 + $rnd.NextDouble() * 8), (3.5 + $rnd.NextDouble() * 5), (0.55 + $rnd.NextDouble() * 0.45)) }
for ($y = 0; $y -lt $size; $y++) {
	for ($x = 0; $x -lt $size; $x++) {
		$dx = $x - $c; $dy = $y - $c
		$d = [math]::Sqrt($dx * $dx + $dy * $dy) / $c
		if ($d -ge 1) { $bmp.SetPixel($x, $y, (C 255 255 255 0)); continue }
		$ang = [math]::Atan2($dy, $dx) * 180 / [math]::PI
		$v = 0.0
		foreach ($r in $rays) {
			$diff = [math]::Abs((($ang - $r[0] + 540) % 360) - 180)
			if ($diff -lt $r[1]) { $v = [math]::Max($v, [math]::Pow(1 - $diff / $r[1], 1.5) * $r[2]) }
		}
		$fade = [math]::Pow(1 - $d, 1.4) * [math]::Min(1, $d * 5)
		$bmp.SetPixel($x, $y, (C 255 255 255 ([int](200 * $v * $fade))))
	}
}
$bmp.Save((Join-Path $OutDir 'Rays_Soft.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"done"
