param([string]$Video, [string]$OutDir, [double[]]$Times, [int]$Count = 12)
# Saves still frames of a video as PNGs (Windows media APIs; no ffmpeg needed).
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Media.Editing.MediaClip, Windows.Media.Editing, ContentType = WindowsRuntime]
$null = [Windows.Media.Editing.MediaComposition, Windows.Media.Editing, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapEncoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, $type) {
	$t = $asTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op))
	$t.Wait() | Out-Null
	$t.Result
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Video)) ([Windows.Storage.StorageFile])
$clip = Await ([Windows.Media.Editing.MediaClip]::CreateFromFileAsync($file)) ([Windows.Media.Editing.MediaClip])
$comp = New-Object Windows.Media.Editing.MediaComposition
[System.Collections.Generic.ICollection[Windows.Media.Editing.MediaClip]].GetMethod('Add').Invoke($comp.Clips, @($clip))
"duration: $($clip.OriginalDuration.TotalSeconds)"
if (-not $Times) {
	$d = $clip.OriginalDuration.TotalSeconds
	$Times = 0..($Count - 1) | ForEach-Object { [math]::Round($_ * $d / $Count, 2) }
}
foreach ($t in $Times) {
	$stream = Await ($comp.GetThumbnailAsync([TimeSpan]::FromSeconds($t), 1280, 0, [Windows.Media.Editing.VideoFramePrecision]::NearestFrame)) ([Windows.Graphics.Imaging.ImageStream])
	$reader = New-Object Windows.Storage.Streams.DataReader($stream)
	$null = Await ($reader.LoadAsync([uint32]$stream.Size)) ([uint32])
	$bytes = New-Object byte[] $stream.Size
	$reader.ReadBytes($bytes)
	$name = Join-Path $OutDir ("f_{0:000.00}.png" -f $t)
	[IO.File]::WriteAllBytes($name, $bytes)
}
"done"
