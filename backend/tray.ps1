<#
    tray.ps1 - App integree Vigie dans la barre systeme.
    - Serveur Pode EN FOND (cache). Icone = STATUT DE L'APP (pas des composants) via /health :
        vert = en marche, orange = demarrage, rouge = erreur/arret. Poll leger toutes les 8 s.
    - "Afficher l'application" -> fenetre DEDIEE (Edge/Chrome en mode --app). "Ouvrir dans le navigateur" -> onglet.
    - "Relancer l'application" recharge le tray. Menu sombre. Enfants lances sans fenetre (CreateNoWindow).
    - Journalise dans logs/tray_*.log. UI en runspace STA. Instance unique.
#>
$ErrorActionPreference = 'Stop'
# URL du depot : CONSTANTE volontaire (pas un reglage) - elle ne doit pas changer facilement.
# Equivalent cote front : REPO_URL dans frontend/index.html.
$RepoUrl = 'https://github.com/Cartman34/vigie-windows'
$backend = $PSScriptRoot
$logDir  = Join-Path $backend 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$trayLog = Join-Path $logDir ('tray_' + (Get-Date -Format 'yyyyMMdd') + '.log')
function TLog($m) { try { ("[" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "] " + $m) | Out-File -FilePath $trayLog -Append -Encoding UTF8 } catch { } }
TLog "demarrage (PS $($PSVersionTable.PSVersion), $([System.Threading.Thread]::CurrentThread.GetApartmentState()))"

$mutex = New-Object System.Threading.Mutex($false, 'VigieTray')
if (-not $mutex.WaitOne(4000)) { TLog "deja lance (mutex) - sortie"; return }

$uiScript = {
    param($backend, $trayLog, $repoUrl)
    $ErrorActionPreference = 'Continue'
    function TLog($m) { try { ("[" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "] " + $m) | Out-File -FilePath $trayLog -Append -Encoding UTF8 } catch { } }
    try {
        . (Join-Path $backend 'lib/common.ps1')
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        Add-Type -Namespace VigieNative -Name Ico -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr handle);'

        $cfg       = Get-Config -Backend $backend
        $url       = Get-AppUrl -Config $cfg
        $healthUrl = (Get-ApiUrl -Config $cfg) + '/health'
        $pwsh      = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        $trayPath  = Join-Path $backend 'tray.ps1'
        $state     = [hashtable]::Synchronized(@{ Proc = $null; Drawn = ''; EverUp = $false; StartTicks = [datetime]::UtcNow.Ticks })
        $iconHandle = [System.IntPtr]::Zero

        $Pt = { param($cx,$cy,$r,$deg) $a = $deg * [math]::PI / 180.0; ,@(($cx + $r * [math]::Cos($a)), ($cy + $r * [math]::Sin($a))) }

        $launchHidden = {
            param($file, $argv)
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $file; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            foreach ($x in $argv) { [void]$psi.ArgumentList.Add([string]$x) }
            return [System.Diagnostics.Process]::Start($psi)
        }
        $startServer = {
            if (Test-ServerUp -Address $cfg.BindAddress -Port $cfg.Port) { return }
            if ($pwsh) { $state.Proc = & $launchHidden $pwsh @('-NoProfile','-ExecutionPolicy','Bypass','-File', (Join-Path $backend 'start.ps1')) }
        }
        $stopServer = { try { if ($state.Proc -and -not $state.Proc.HasExited) { $state.Proc.Kill() } } catch { } }
        $relaunch = {
            try { [void](& $launchHidden $pwsh @('-NoProfile','-ExecutionPolicy','Bypass','-File', $trayPath)) } catch { }
            $icon.Visible = $false; $icon.Dispose(); [System.Windows.Forms.Application]::Exit()
        }
        $openApp = {
            $bases = @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:LOCALAPPDATA) | Where-Object { $_ }
            $rel = @('Microsoft\Edge\Application\msedge.exe','Google\Chrome\Application\chrome.exe')
            $b = $null
            foreach ($base in $bases) { foreach ($rp in $rel) { $cand = Join-Path $base $rp; if (Test-Path $cand) { $b = $cand; break } }; if ($b) { break } }
            if ($b) { try { Start-Process -FilePath $b -ArgumentList "--app=$url","--window-size=1240,840" } catch { Start-Process $url } }
            else    { Start-Process $url }
        }
        $openUrl     = { param($u) try { Start-Process $u } catch { TLog ("ouverture KO (" + $u + ") : " + $_.Exception.Message) } }
        $openBrowser = { & $openUrl $url }
        $openRepo    = { & $openUrl $repoUrl }

        $icon = New-Object System.Windows.Forms.NotifyIcon
        $icon.Text = 'Vigie'

        $setIcon = {
            param($status)
            # Icone = fichier .ico multi-resolutions (net). Repli sur le dessin GDI+ si absent.
            $name = switch ($status) { 'ok' { 'ok' } 'warn' { 'warn' } 'error' { 'error' } default { 'error' } }
            $icoPath = Join-Path $backend ('assets\tray\' + $name + '.ico')
            if (Test-Path $icoPath) {
                try {
                    $newIco = New-Object System.Drawing.Icon($icoPath)
                    $icon.Icon = $newIco
                    if ($script:iconObj) { try { $script:iconObj.Dispose() } catch { } }
                    $script:iconObj = $newIco
                    return
                } catch { }
            }
            $c = switch ($status) {
                'ok'    { [System.Drawing.Color]::FromArgb(63,185,80) }
                'warn'  { [System.Drawing.Color]::FromArgb(210,153,34) }
                'error' { [System.Drawing.Color]::FromArgb(248,81,73) }
                default { [System.Drawing.Color]::FromArgb(248,81,73) }
            }
            $frac = switch ($status) { 'ok' { 0.88 } 'warn' { 0.5 } 'error' { 0.14 } default { 0.14 } }
            $s = 32.0; $cx = $s/2; $cy = $s/2; $r = $s*0.35; $sw = $s*0.13
            $a0 = 135.0; $span = 270.0; $ang = $a0 + $frac*$span
            $bmp = New-Object System.Drawing.Bitmap ([int]$s), ([int]$s)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::Transparent)
            $track = [System.Drawing.Color]::FromArgb(70,78,88)
            $dark  = [System.Drawing.Color]::FromArgb(242, [int]($c.R*0.72), [int]($c.G*0.72), [int]($c.B*0.72))
            $tick  = [System.Drawing.Color]::FromArgb(120,160,168,176)
            $ringC = [System.Drawing.Color]::FromArgb(120, $c.R, $c.G, $c.B)
            $white = [System.Drawing.Color]::FromArgb(245,250,255)
            $rr = $s*0.45
            $penRing = New-Object System.Drawing.Pen ($ringC, [single]($s*0.03))
            $g.DrawEllipse($penRing, [single]($cx-$rr), [single]($cy-$rr), [single](2*$rr), [single](2*$rr)); $penRing.Dispose()
            $penTrack = New-Object System.Drawing.Pen ($track, [single]$sw); $penTrack.StartCap='Round'; $penTrack.EndCap='Round'
            $g.DrawArc($penTrack, [single]($cx-$r), [single]($cy-$r), [single](2*$r), [single](2*$r), [single]$a0, [single]$span); $penTrack.Dispose()
            $penVal = New-Object System.Drawing.Pen ($c, [single]$sw); $penVal.StartCap='Round'; $penVal.EndCap='Round'
            $g.DrawArc($penVal, [single]($cx-$r), [single]($cy-$r), [single](2*$r), [single](2*$r), [single]$a0, [single]($frac*$span)); $penVal.Dispose()
            $np = (& $Pt $cx $cy ($r*0.94) $ang)[0]; $tp = @($cx, $cy)
            $penLis = New-Object System.Drawing.Pen ($dark, [single]($s*0.118)); $penLis.StartCap='Round'; $penLis.EndCap='Round'
            $g.DrawLine($penLis, [single]$tp[0], [single]$tp[1], [single]$np[0], [single]$np[1]); $penLis.Dispose()
            $penNeedle = New-Object System.Drawing.Pen ($c, [single]($s*0.10)); $penNeedle.StartCap='Round'; $penNeedle.EndCap='Round'
            $g.DrawLine($penNeedle, [single]$tp[0], [single]$tp[1], [single]$np[0], [single]$np[1]); $penNeedle.Dispose()
            $hr = $s*0.11
            $g.FillEllipse((New-Object System.Drawing.SolidBrush $c), [single]($cx-$hr), [single]($cy-$hr), [single](2*$hr), [single](2*$hr))
            $wr = $s*0.05
            $g.FillEllipse((New-Object System.Drawing.SolidBrush $white), [single]($cx-$wr), [single]($cy-$wr), [single](2*$wr), [single](2*$wr))
            $g.Dispose()
            $h = $bmp.GetHicon(); $bmp.Dispose()
            $icon.Icon = [System.Drawing.Icon]::FromHandle($h)
            if ($iconHandle -ne [System.IntPtr]::Zero) { [void][VigieNative.Ico]::DestroyIcon($iconHandle) }
            $script:iconHandle = $h
        }
        & $setIcon 'warn'
        $icon.Visible = $true
        TLog "icone visible"

        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        $menu.ShowImageMargin = $false
        try { $menu.Font = New-Object System.Drawing.Font('Segoe UI', 9.5) } catch { }
        try {
            $csrc = @"
public class VigieDarkColors : System.Windows.Forms.ProfessionalColorTable {
  static System.Drawing.Color BG = System.Drawing.Color.FromArgb(28,33,40);
  static System.Drawing.Color HI = System.Drawing.Color.FromArgb(55,62,71);
  static System.Drawing.Color BD = System.Drawing.Color.FromArgb(68,76,86);
  public override System.Drawing.Color ToolStripDropDownBackground { get { return BG; } }
  public override System.Drawing.Color ImageMarginGradientBegin { get { return BG; } }
  public override System.Drawing.Color ImageMarginGradientMiddle { get { return BG; } }
  public override System.Drawing.Color ImageMarginGradientEnd { get { return BG; } }
  public override System.Drawing.Color MenuBorder { get { return BD; } }
  public override System.Drawing.Color MenuItemBorder { get { return HI; } }
  public override System.Drawing.Color MenuItemSelected { get { return HI; } }
  public override System.Drawing.Color MenuItemSelectedGradientBegin { get { return HI; } }
  public override System.Drawing.Color MenuItemSelectedGradientEnd { get { return HI; } }
  public override System.Drawing.Color MenuItemPressedGradientBegin { get { return BG; } }
  public override System.Drawing.Color MenuItemPressedGradientEnd { get { return BG; } }
  public override System.Drawing.Color SeparatorDark { get { return BD; } }
  public override System.Drawing.Color SeparatorLight { get { return BD; } }
}
"@
            Add-Type -TypeDefinition $csrc -ReferencedAssemblies @([System.Windows.Forms.ToolStrip].Assembly.Location, [System.Drawing.Color].Assembly.Location) -ErrorAction Stop
            $menu.Renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer ([VigieDarkColors]::new())
            $menu.BackColor = [System.Drawing.Color]::FromArgb(28,33,40)
            $menu.ForeColor = [System.Drawing.Color]::FromArgb(230,237,243)
            TLog "menu sombre applique"
        } catch { TLog ("style menu KO (fallback): " + $_.Exception.Message) }

        $lite = [System.Drawing.Color]::FromArgb(230,237,243)
        $miShow = $menu.Items.Add('Afficher l''application', $null, [System.EventHandler]{ & $openApp })
        $miShow.ForeColor = $lite
        try { $miShow.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold) } catch { }
        $miWeb = $menu.Items.Add('Ouvrir dans le navigateur', $null, [System.EventHandler]{ & $openBrowser })
        $miWeb.ForeColor = $lite
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        $miInfo = New-Object System.Windows.Forms.ToolStripLabel('Etat : demarrage...')
        $miInfo.ForeColor = [System.Drawing.Color]::FromArgb(139,148,158)
        [void]$menu.Items.Add($miInfo)
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        $mi1 = $menu.Items.Add('Relancer l''application', $null, [System.EventHandler]$relaunch)
        $mi2 = $menu.Items.Add('Redémarrer le serveur', $null, [System.EventHandler]{ & $stopServer; Start-Sleep -Milliseconds 600; & $startServer })
        $mi3 = $menu.Items.Add('Ouvrir les journaux', $null, [System.EventHandler]{ Start-Process (Get-LogDir -Backend $backend) })
        $mi4 = $menu.Items.Add('À propos de Vigie', $null, [System.EventHandler]{ & $openRepo })
        $mi4.ToolTipText = $repoUrl
        foreach ($mi in @($mi1,$mi2,$mi3,$mi4)) { $mi.ForeColor = $lite }
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        $miQuit = $menu.Items.Add('Quitter', $null, [System.EventHandler]{ & $stopServer; $icon.Visible = $false; $icon.Dispose(); [System.Windows.Forms.Application]::Exit() })
        $miQuit.ForeColor = $lite
        $icon.ContextMenuStrip = $menu
        $icon.add_MouseDoubleClick({ & $openApp })

        & $startServer
        TLog "serveur ok"

        $poll = {
            try {
                [void](Invoke-RestMethod -Uri $healthUrl -TimeoutSec 5 -ErrorAction Stop)
                $state.EverUp = $true
                $app = 'ok'; $lbl = 'En marche'
            } catch {
                $elapsed = ([datetime]::UtcNow.Ticks - $state.StartTicks) / 1e7
                if ($state.EverUp) { $app = 'error'; $lbl = 'Arretee / injoignable' }
                elseif ($elapsed -gt 25) { $app = 'error'; $lbl = 'Echec de demarrage' }
                else { $app = 'warn'; $lbl = 'Demarrage...' }
            }
            $miInfo.Text = "Etat : $lbl"
            if ($app -ne $state.Drawn) { & $setIcon $app; $state.Drawn = $app; $icon.Text = "Vigie - $lbl"; TLog "app=$app" }
        }
        $timer = New-Object System.Windows.Forms.Timer; $timer.Interval = 8000; $timer.add_Tick($poll); $timer.Start()
        $first = New-Object System.Windows.Forms.Timer; $first.Interval = 2000; $first.add_Tick({ $first.Stop(); & $poll }); $first.Start()

        try { $icon.ShowBalloonTip(3000, 'Vigie', "Panneau lance en fond. Double-cliquez l'icone pour l'ouvrir.", [System.Windows.Forms.ToolTipIcon]::Info) } catch { }

        TLog "Application.Run"
        [System.Windows.Forms.Application]::Run()
        if ($iconHandle -ne [System.IntPtr]::Zero) { [void][VigieNative.Ico]::DestroyIcon($iconHandle) }
        TLog "sortie boucle"
    } catch { TLog ("ERREUR UI: " + $_.Exception.ToString()) }
}

$rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
$ps = [PowerShell]::Create(); $ps.Runspace = $rs
[void]$ps.AddScript($uiScript).AddArgument($backend).AddArgument($trayLog).AddArgument($RepoUrl)
try { $ps.Invoke() } catch { TLog ("ERREUR Invoke: " + $_.Exception.ToString()) }
foreach ($er in $ps.Streams.Error) { TLog ("STREAM ERROR: " + $er.ToString()) }
try { $rs.Close() } catch { }
try { $mutex.ReleaseMutex() } catch { }
TLog "termine"
