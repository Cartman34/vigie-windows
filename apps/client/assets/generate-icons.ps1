# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    generate-icons.ps1 - THE CLIENT APP'S ICONS: ok / warn / error, as .ico.

    WHY POWERSHELL AND NOT PYTHON ANY MORE. D41: PowerShell is the tool for WINDOWS tools -- that is its reason to
    exist here -- and PHP is the default for everything else; a .py file is a decision, never a habit. These icons are
    the mark of the client app in the notification area, drawn with GDI+, which ships with the system, where the Python version needed Pillow installed
    on every machine that might ever want to redraw the mark. S08 counted that file, and this one replaces it.

    WHAT IT DRAWS, AND WHY IT IS NOT ONE DRAWING SCALED DOWN. A detail designed for 256 px does not survive a
    reduction to 16: the thin ring and the thick arc merge into an unreadable blob. So EVERY SIZE IS DRAWN AT ITS OWN
    RESOLUTION, with the level of detail that size can carry (D37) -- what would become noise is removed before it
    becomes noise. Each size is drawn at 8x then reduced, so the edges stay clean whatever the filter does.

    GEOMETRY: D01 for the proportions, D23 for the level fractions, D27 for the ticks under the arc, D37 for the
    levels of detail. A value changed here must be mirrored in the Atelier (apps/atelier/index.html), which simulates
    the same mark. The client app does NOT redraw it: it loads these files, and its degraded mode is a plain disc on
    purpose -- two drawings of one mark had already drifted apart once.

    GDI+ STROKES ON THE PATH, like SVG. The Python version carried a long comment about Pillow thickening INWARDS
    from the bounding box, and the half-width correction that needed; none of that belongs here. A rectangle of radius
    r gives a stroke centred on r, which is what the design says, and round caps come from the pen rather than from
    discs added by hand at each end.

    Usage:  pwsh -File apps/client/assets/generate-icons.ps1 [-Out <folder>] [-Check]
            Default folder: this one. Writes ok.ico, warn.ico and error.ico, and nothing else.
#>
param(
    [string] $Out = $PSScriptRoot,
    # Draw everything and report, without writing: used to compare a rewrite against what is in place.
    [switch] $Check
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# --- The mark, in fractions of the size (D01) -------------------------------------------
$A0     = 135.0     # where the gauge starts
$SPAN   = 270.0     # how far it sweeps
$R_ARC  = 0.35      # radius of the gauge arc
$R_RING = 0.45      # radius of the outer ring
$TRACK = [System.Drawing.Color]::FromArgb(255, 0x30, 0x36, 0x3d)   # the arc's unfilled track
$TICK  = [System.Drawing.Color]::FromArgb(89,  0x8b, 0x94, 0x9e)   # ticks, 35 % opacity
$WHITE = [System.Drawing.Color]::FromArgb(255, 0xf0, 0xf6, 0xfc)   # the dot at the centre

# Below a number of pixels an element stops being legible and becomes noise: this is the
# smallest icon size from which each one is drawn at all (D37).
$DETAIL = @{ ring = 48; ticks = 64; edge = 32 }

# The smaller the icon, the thicker the strokes must be to stay readable.
function Get-StrokeWidths([int]$size) {
    if ($size -ge 48) { return @{ arc = 0.110; needle = 0.082; edge = 0.098; hub = 0.095; dot = 0.042 } }
    if ($size -ge 32) { return @{ arc = 0.125; needle = 0.095; edge = 0.112; hub = 0.105; dot = 0.046 } }
    # 16 to 24 px: a simplified mark that READS, rather than a faithful reduction that does not.
    return @{ arc = 0.150; needle = 0.115; edge = 0.000; hub = 0.125; dot = 0.052 }
}

function Get-Darker([System.Drawing.Color]$c, [double]$f, [int]$alpha) {
    [System.Drawing.Color]::FromArgb($alpha, [int]($c.R * $f), [int]($c.G * $f), [int]($c.B * $f))
}

# A point at (radius, degrees) around a centre, y downwards -- the same convention as GDI+ arcs.
function Get-MarkPoint([double]$cx, [double]$cy, [double]$radius, [double]$deg) {
    $a = $deg * [Math]::PI / 180.0
    return [System.Drawing.PointF]::new([single]($cx + $radius * [Math]::Cos($a)), [single]($cy + $radius * [Math]::Sin($a)))
}
function New-RoundPen([System.Drawing.Color]$c, [double]$width) {
    $p = New-Object System.Drawing.Pen $c, ([single]$width)
    $p.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $p.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    return $p
}

function New-MarkBitmap {
    param([int]$Size, [System.Drawing.Color]$Color, [double]$Fraction, [int]$Supersample = 8)

    $m  = $Size * $Supersample
    $w  = Get-StrokeWidths $Size
    $cx = $m / 2.0
    $cy = $m / 2.0
    $r  = $m * $R_ARC

    $big = New-Object System.Drawing.Bitmap $m, $m, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g   = [System.Drawing.Graphics]::FromImage($big)
    try {
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.Clear([System.Drawing.Color]::Transparent)

        # 1) The outer ring -- only when it has room to exist.
        if ($Size -ge $DETAIL.ring) {
            $rr  = $m * $R_RING
            $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(89, $Color.R, $Color.G, $Color.B)), ([single][Math]::Max(1, [Math]::Round($m * 0.024)))
            $g.DrawEllipse($pen, [single]($cx - $rr), [single]($cy - $rr), [single](2 * $rr), [single](2 * $rr))
            $pen.Dispose()
        }

        # 2) The track, then the ticks, then the value arc ON TOP (D27).
        $sw   = $m * $w.arc
        $rect = New-Object System.Drawing.RectangleF ([single]($cx - $r)), ([single]($cy - $r)), ([single](2 * $r)), ([single](2 * $r))
        $pen  = New-RoundPen $TRACK $sw
        $g.DrawArc($pen, $rect, [single]$A0, [single]$SPAN)
        $pen.Dispose()

        if ($Size -ge $DETAIL.ticks) {
            $pen = New-Object System.Drawing.Pen $TICK, ([single][Math]::Max(1, [Math]::Round($m * 0.02)))
            foreach ($i in 0..6) {                      # 7 ticks, both bounds included (D01)
                $a  = $A0 + ($i / 6.0) * $SPAN
                $p0 = Get-MarkPoint $cx $cy ($r * 0.98) $a
                $p1 = Get-MarkPoint $cx $cy ($r * 0.80) $a
                $g.DrawLine($pen, $p0, $p1)
            }
            $pen.Dispose()
        }

        $ang = $A0 + $Fraction * $SPAN
        $pen = New-RoundPen $Color $sw
        $g.DrawArc($pen, $rect, [single]$A0, [single]($ang - $A0))
        $pen.Dispose()

        # 3) The needle -- its dark edge disappears when it would be under one pixel.
        $heel = Get-MarkPoint $cx $cy (-$m * 0.06) $ang
        $tip  = Get-MarkPoint $cx $cy ($r * 0.92) $ang
        if ($Size -ge $DETAIL.edge -and $w.edge -gt 0) {
            $pen = New-RoundPen (Get-Darker $Color 0.72 242) ($m * $w.edge)
            $g.DrawLine($pen, $heel, $tip)
            $pen.Dispose()
        }
        $pen = New-RoundPen $Color ($m * $w.needle)
        $g.DrawLine($pen, $heel, $tip)
        $pen.Dispose()

        # 4) The hub, and the dot at the centre.
        $hr = $m * $w.hub
        $br = New-Object System.Drawing.SolidBrush $Color
        $g.FillEllipse($br, [single]($cx - $hr), [single]($cy - $hr), [single](2 * $hr), [single](2 * $hr))
        $br.Dispose()
        $wr = $m * $w.dot
        $br = New-Object System.Drawing.SolidBrush $WHITE
        $g.FillEllipse($br, [single]($cx - $wr), [single]($cy - $wr), [single](2 * $wr), [single](2 * $wr))
        $br.Dispose()
    } finally { $g.Dispose() }

    # The reduction to the real size, in one high-quality step.
    $small = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g2 = [System.Drawing.Graphics]::FromImage($small)
    try {
        $g2.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g2.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g2.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g2.Clear([System.Drawing.Color]::Transparent)
        $g2.DrawImage($big, (New-Object System.Drawing.Rectangle 0, 0, $Size, $Size))
    } finally { $g2.Dispose(); $big.Dispose() }
    return $small
}

<#
    THE .ICO CONTAINER, WRITTEN BY HAND, BECAUSE .NET CANNOT.

    System.Drawing.Icon READS an .ico and hands back one frame; nothing in .NET WRITES a
    multi-size one. The format is small enough to write: a 6-byte header, one 16-byte entry
    per image, then the images themselves. Each image is stored as a PNG -- what the Python
    version produced, and what Windows has read since Vista -- so a frame is exactly the
    bytes of its own PNG, with nothing to recompute and no palette to build.

    The width and height bytes are 0 for 256: the field holds ONE byte, and 256 does not fit
    in it. That zero is the format's convention, not an omission.
#>
function Write-IcoFile {
    param([Parameter(Mandatory)][System.Drawing.Bitmap[]]$Frames, [Parameter(Mandatory)][string]$Path)

    $pngs = @()
    foreach ($f in $Frames) {
        $ms = New-Object IO.MemoryStream
        $f.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngs += , $ms.ToArray()
        $ms.Dispose()
    }

    $stream = New-Object IO.MemoryStream
    $bw     = New-Object IO.BinaryWriter $stream
    $bw.Write([uint16]0)                 # reserved
    $bw.Write([uint16]1)                 # type 1 = icon
    $bw.Write([uint16]$Frames.Count)
    $offset = 6 + 16 * $Frames.Count
    for ($i = 0; $i -lt $Frames.Count; $i++) {
        $side  = $Frames[$i].Width
        $octet = [byte]$(if ($side -ge 256) { 0 } else { $side })
        $bw.Write($octet)                # width
        $bw.Write($octet)                # height
        $bw.Write([byte]0)               # palette colours: none, it is a PNG
        $bw.Write([byte]0)               # reserved
        $bw.Write([uint16]1)             # colour planes
        $bw.Write([uint16]32)            # bits per pixel
        $bw.Write([uint32]$pngs[$i].Length)
        $bw.Write([uint32]$offset)
        $offset += $pngs[$i].Length
    }
    foreach ($p in $pngs) { $bw.Write($p) }
    $bw.Flush()
    [IO.File]::WriteAllBytes($Path, $stream.ToArray())
    $bw.Dispose(); $stream.Dispose()
}

# Level fractions (D23): compliant = a FULL gauge.
$MARKS = @(
    @{ Name = 'ok';    Color = [System.Drawing.Color]::FromArgb(255, 63, 185, 80);  Fraction = 1.00 }
    @{ Name = 'warn';  Color = [System.Drawing.Color]::FromArgb(255, 210, 153, 34); Fraction = 0.50 }
    @{ Name = 'error'; Color = [System.Drawing.Color]::FromArgb(255, 248, 81, 73);  Fraction = 0.17 }
)
$SIZES = @(16, 20, 24, 32, 48, 256)

if (-not (Test-Path -LiteralPath $Out -PathType Container)) { Write-Error "dossier introuvable : $Out"; exit 1 }

foreach ($mk in $MARKS) {
    $frames = @()
    foreach ($s in $SIZES) { $frames += New-MarkBitmap -Size $s -Color $mk.Color -Fraction $mk.Fraction }
    $dest = Join-Path $Out ($mk.Name + '.ico')
    if ($Check) {
        $tmp = [IO.Path]::GetTempFileName()
        Write-IcoFile -Frames $frames -Path $tmp
        $neuf  = (Get-Item -LiteralPath $tmp).Length
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        $vieux = if (Test-Path -LiteralPath $dest) { (Get-Item -LiteralPath $dest).Length } else { 0 }
        '{0,-6} {1} image(s) {2} : {3} o ; en place {4} o' -f $mk.Name, $frames.Count, ($SIZES -join '/'), $neuf, $vieux
    } else {
        Write-IcoFile -Frames $frames -Path $dest
        '{0,-6} ecrit : {1} image(s) {2}, {3} o' -f $mk.Name, $frames.Count, ($SIZES -join '/'), (Get-Item -LiteralPath $dest).Length
    }
    foreach ($f in $frames) { $f.Dispose() }
}
