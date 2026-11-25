# アイコン（app.ico / tray-light.ico / tray-dark.ico）を生成する
# どれも「角丸の枠の中にプロンプト記号 >_」の図柄。ICO の中身は複数サイズの PNG。
param([string]$OutDir = $PSScriptRoot)
Add-Type -AssemblyName System.Drawing

function New-RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $gp = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $d = $r * 2
    $gp.AddArc($x, $y, $d, $d, 180, 90)
    $gp.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $gp.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $gp.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $gp.CloseFigure()
    return $gp
}

# $Style: app（塗りつぶし・色付き） / mono（枠線のみ・単色）
function New-IconBitmap([int]$Size, [string]$Style, [System.Drawing.Color]$Fg, [System.Drawing.Color]$Bg) {
    $bmp = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.Clear([System.Drawing.Color]::Transparent)
    $s = $Size / 16.0
    $stroke = [math]::Max(1.0, 1.6 * $s)
    if ($Style -eq 'app') {
        $rr = New-RoundRect (0.5 * $s) (0.5 * $s) (15 * $s) (15 * $s) (3.5 * $s)
        $g.FillPath([System.Drawing.SolidBrush]::new($Bg), $rr)
    } else {
        $inset = $stroke / 2 + 0.5 * $s
        $rr = New-RoundRect $inset $inset ($Size - 2 * $inset) ($Size - 2 * $inset) (3 * $s)
        $pen = [System.Drawing.Pen]::new($Fg, [math]::Max(1.0, 1.2 * $s))
        $g.DrawPath($pen, $rr)
    }
    $pen = [System.Drawing.Pen]::new($Fg, $stroke)
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
    # > と _
    $g.DrawLines($pen, [System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new(4.3 * $s, 5.0 * $s),
        [System.Drawing.PointF]::new(7.3 * $s, 8.0 * $s),
        [System.Drawing.PointF]::new(4.3 * $s, 11.0 * $s)))
    $g.DrawLine($pen, 8.8 * $s, 11.0 * $s, 11.8 * $s, 11.0 * $s)
    $g.Dispose()
    return $bmp
}

function Save-Ico([string]$Path, [System.Drawing.Bitmap[]]$Bitmaps) {
    $pngs = foreach ($b in $Bitmaps) {
        $ms = [IO.MemoryStream]::new(); $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); , $ms.ToArray()
    }
    $fs = [IO.File]::Create($Path)
    $w = [IO.BinaryWriter]::new($fs)
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$Bitmaps.Count)
    $offset = 6 + 16 * $Bitmaps.Count
    for ($i = 0; $i -lt $Bitmaps.Count; $i++) {
        $sz = $Bitmaps[$i].Width
        $w.Write([byte]($(if ($sz -ge 256) { 0 } else { $sz })))
        $w.Write([byte]($(if ($sz -ge 256) { 0 } else { $sz })))
        $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([uint16]1); $w.Write([uint16]32)
        $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
        $offset += $pngs[$i].Length
    }
    foreach ($p in $pngs) { $w.Write($p) }
    $w.Dispose()
}

$white = [System.Drawing.Color]::White
$black = [System.Drawing.Color]::FromArgb(255, 28, 28, 28)
$clay  = [System.Drawing.Color]::FromArgb(255, 0xD9, 0x77, 0x57)

Save-Ico (Join-Path $OutDir 'app.ico')        @(16, 20, 24, 32, 48, 64, 256 | ForEach-Object { New-IconBitmap $_ 'app' $white $clay })
Save-Ico (Join-Path $OutDir 'tray-light.ico') @(16, 20, 24, 32, 40, 48 | ForEach-Object { New-IconBitmap $_ 'mono' $white $white })
Save-Ico (Join-Path $OutDir 'tray-dark.ico')  @(16, 20, 24, 32, 40, 48 | ForEach-Object { New-IconBitmap $_ 'mono' $black $black })
# 確認用のプレビュー
$prev = [System.Drawing.Bitmap]::new(200, 70)
$g = [System.Drawing.Graphics]::FromImage($prev); $g.Clear([System.Drawing.Color]::FromArgb(255, 128, 128, 128))
$g.DrawImage((New-IconBitmap 64 'app' $white $clay), 2, 3)
$g.DrawImage((New-IconBitmap 32 'mono' $white $white), 80, 19)
$g.DrawImage((New-IconBitmap 32 'mono' $black $black), 130, 19)
$g.DrawImage((New-IconBitmap 16 'mono' $white $white), 170, 27)
$g.Dispose()
$prev.Save((Join-Path $env:TEMP 'cc-launcher-icons-preview.png'))
Get-ChildItem $OutDir -Filter *.ico | Select-Object Name, Length
