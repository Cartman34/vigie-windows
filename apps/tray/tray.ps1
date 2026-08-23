<#
    tray.ps1 - App Vigie de la barre systeme (apps/tray).

    C'est une app A PART ENTIERE, distincte du backend : elle a son interface
    WinForms, ses icones (assets/) et son cycle de vie. Elle PILOTE le backend
    (le demarre, l'arrete, sonde sa sante) sans en faire partie.
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
# Le backend est une app SOEUR (apps/backend), pas le dossier courant.
$appsRoot = Split-Path $PSScriptRoot -Parent
$backend  = Join-Path $appsRoot 'backend-pode'   # BOOTSTRAP : nom en clair, cf. common.ps1
$repoRoot = Split-Path $appsRoot -Parent
$logDir  = Join-Path $repoRoot 'logs'      # journaux communs a toutes les apps
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$trayLog = Join-Path $logDir ('tray_' + (Get-Date -Format 'yyyyMMdd') + '.log')
function TLog($m) { try { ("[" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "] " + $m) | Out-File -FilePath $trayLog -Append -Encoding UTF8 } catch { } }
TLog "demarrage (PS $($PSVersionTable.PSVersion), $([System.Threading.Thread]::CurrentThread.GetApartmentState()))"

$mutex = New-Object System.Threading.Mutex($false, 'VigieTray')
if (-not $mutex.WaitOne(4000)) { TLog "deja lance (mutex) - sortie"; return }

$uiScript = {
    param($backend, $trayLog, $repoUrl, $trayRoot)
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
        $trayPath  = Join-Path $trayRoot 'tray.ps1'      # cette app, pas le backend
        # Starting : un demarrage a ete demande et le serveur n'a pas encore repondu.
        $state     = [hashtable]::Synchronized(@{ Proc = $null; Drawn = ''; EverUp = $false; Starting = $true; StartTicks = [datetime]::UtcNow.Ticks })
        $startupGrace = 25    # secondes de tolerance avant de declarer un echec de demarrage
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
            # Un demarrage VOULU rouvre la fenetre de tolerance : pendant $startupGrace
            # secondes, "injoignable" veut dire "demarre" (orange) et non "en panne" (rouge).
            $state.StartTicks = [datetime]::UtcNow.Ticks
            $state.Starting   = $true
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
            $icoPath = Join-Path $trayRoot ('assets\' + $name + '.ico')   # icones de CETTE app
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
            # Fractions IDENTIQUES a assets/generer-icones.py : conforme = jauge pleine.
            $frac = switch ($status) { 'ok' { 1.0 } 'warn' { 0.5 } 'error' { 0.14 } default { 0.14 } }
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
        # --- Style Win11 : coins arrondis natifs (DWM), survol encarte arrondi ---
        # Tout echec retombe silencieusement sur le rendu par defaut : le menu reste
        # utilisable meme si le style ne s'applique pas.
        try {
            $csrc = @'
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

// Palette du menu. Une seule definition des couleurs, partagee par la table et le rendu.
public static class VigieMenuPalette {
  public static readonly Color Surface   = Color.FromArgb(43, 48, 56);
  public static readonly Color Hover     = Color.FromArgb(60, 67, 77);
  public static readonly Color Border    = Color.FromArgb(68, 76, 86);
  public static readonly Color Separator = Color.FromArgb(58, 65, 74);
  public const int CornerRadius = 5;   // arrondi du RECTANGLE DE SURVOL
  public const int MenuRadius   = 8;   // arrondi des COINS DU MENU (decoupe de region)
  public const int InsetX       = 5;   // marge laterale du rectangle de survol
  public const int InsetY       = 2;
}

public class VigieDarkColors : ProfessionalColorTable {
  public override Color ToolStripDropDownBackground { get { return VigieMenuPalette.Surface; } }
  public override Color ImageMarginGradientBegin    { get { return VigieMenuPalette.Surface; } }
  public override Color ImageMarginGradientMiddle   { get { return VigieMenuPalette.Surface; } }
  public override Color ImageMarginGradientEnd      { get { return VigieMenuPalette.Surface; } }
  public override Color MenuBorder                  { get { return VigieMenuPalette.Border; } }
  public override Color MenuItemBorder              { get { return VigieMenuPalette.Hover; } }
  public override Color MenuItemSelected            { get { return VigieMenuPalette.Hover; } }
  public override Color MenuItemSelectedGradientBegin { get { return VigieMenuPalette.Hover; } }
  public override Color MenuItemSelectedGradientEnd   { get { return VigieMenuPalette.Hover; } }
  public override Color MenuItemPressedGradientBegin  { get { return VigieMenuPalette.Surface; } }
  public override Color MenuItemPressedGradientEnd    { get { return VigieMenuPalette.Surface; } }
  public override Color SeparatorDark               { get { return VigieMenuPalette.Separator; } }
  public override Color SeparatorLight              { get { return VigieMenuPalette.Separator; } }
}

public class VigieMenuRenderer : ToolStripProfessionalRenderer {
  public VigieMenuRenderer() : base(new VigieDarkColors()) { this.RoundedEdges = false; }

  static GraphicsPath RoundedRect(Rectangle r, int radius) {
    int d = radius * 2;
    GraphicsPath p = new GraphicsPath();
    if (d <= 0 || r.Width <= d || r.Height <= d) { p.AddRectangle(r); return p; }
    p.AddArc(r.X, r.Y, d, d, 180, 90);
    p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
    p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
    p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
    p.CloseFigure();
    return p;
  }

  // Survol : rectangle ENCARTE et arrondi (Win11), et non une bande pleine largeur.
  protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
    if (!e.Item.Selected || !e.Item.Enabled) return;
    Rectangle b = new Rectangle(Point.Empty, e.Item.Size);
    Rectangle r = new Rectangle(
      b.X + VigieMenuPalette.InsetX,
      b.Y + VigieMenuPalette.InsetY,
      b.Width  - VigieMenuPalette.InsetX * 2,
      b.Height - VigieMenuPalette.InsetY * 2);
    if (r.Width <= 0 || r.Height <= 0) return;
    SmoothingMode old = e.Graphics.SmoothingMode;
    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
    using (GraphicsPath path = RoundedRect(r, VigieMenuPalette.CornerRadius))
    using (SolidBrush brush = new SolidBrush(VigieMenuPalette.Hover))
      e.Graphics.FillPath(brush, path);
    e.Graphics.SmoothingMode = old;
  }

  // Separateur : trait fin encarte, aligne sur les marges du survol.
  protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e) {
    Rectangle b = new Rectangle(Point.Empty, e.Item.Size);
    int y = b.Top + b.Height / 2;
    using (Pen pen = new Pen(VigieMenuPalette.Separator))
      e.Graphics.DrawLine(pen, b.Left + VigieMenuPalette.InsetX + 3, y, b.Right - VigieMenuPalette.InsetX - 3, y);
  }

  // Fond uni : pas de degrade, pas de bande de marge d'icone.
  protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e) {
    using (SolidBrush brush = new SolidBrush(VigieMenuPalette.Surface))
      e.Graphics.FillRectangle(brush, e.AffectedBounds);
  }

  // Bordure geree par DWM (coins arrondis natifs) : ne rien dessiner ici.
  protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e) { }
}
'@
            # System.Drawing est scinde : Color vient de System.Drawing.Primitives,
            # GraphicsPath/Graphics de System.Drawing.Common. Il faut les DEUX.
            $refs = @(
                [System.Windows.Forms.ToolStrip].Assembly.Location,
                [System.Drawing.Color].Assembly.Location,
                [System.Drawing.Drawing2D.GraphicsPath].Assembly.Location
            ) | Sort-Object -Unique
            Add-Type -TypeDefinition $csrc -ReferencedAssemblies $refs -ErrorAction Stop
            $menu.Renderer  = New-Object VigieMenuRenderer
            $menu.BackColor = [VigieMenuPalette]::Surface
            $menu.ForeColor = [System.Drawing.Color]::FromArgb(230,237,243)
            $menu.Padding   = New-Object System.Windows.Forms.Padding(0, 5, 0, 5)
            TLog "style menu Win11 applique"
        } catch { TLog ("style menu KO (fallback): " + $_.Exception.Message) }

        # Coins arrondis NATIFS via DWM (Windows 11). Applique a chaque ouverture :
        # idempotent, et la fenetre du menu peut recreer son handle entre deux affichages.
        # Set-WindowChrome vient de lib/common.ps1 : la signature P/Invoke n'est
        # declaree qu'a un seul endroit, partage avec la fenetre de consentement.
        # DWM d'abord (ombre et anticrenelage natifs quand il veut bien s'appliquer),
        # puis decoupe de region qui, elle, arrondit TOUJOURS : sans elle le menu reste
        # a coins carres, DWM n'arrondissant pas les fenetres sans cadre standard.
        $roundCorners = {
            Set-WindowChrome  -Handle $menu.Handle -RoundedCorners -BorderColor 0x00564C44
            Set-RoundedRegion -Control $menu -Radius ([VigieMenuPalette]::MenuRadius)
        }
        $menu.add_Opened({ & $roundCorners })

        $lite = [System.Drawing.Color]::FromArgb(230,237,243)
        $miShow = $menu.Items.Add('Afficher l''application', $null, [System.EventHandler]{ & $openApp })
        try { $miShow.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold) } catch { }
        [void]$menu.Items.Add('Ouvrir dans le navigateur', $null, [System.EventHandler]{ & $openBrowser })
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        $miInfo = New-Object System.Windows.Forms.ToolStripLabel('État : démarrage…')
        $miInfo.ForeColor = [System.Drawing.Color]::FromArgb(139,148,158)
        [void]$menu.Items.Add($miInfo)
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        [void]$menu.Items.Add('Relancer l''application', $null, [System.EventHandler]$relaunch)
        [void]$menu.Items.Add('Redémarrer le serveur', $null, [System.EventHandler]{
            & $stopServer
            Start-Sleep -Milliseconds 600
            & $startServer
            # Retour visuel immediat : sans cela l'icone garde son etat jusqu'au prochain
            # sondage (8 s) et l'utilisateur voit un rouge qui n'a pas lieu d'etre.
            & $setIcon 'warn'; $state.Drawn = 'warn'
            $icon.Text = 'Vigie - Démarrage…'; $miInfo.Text = 'État : Démarrage…'
        })
        [void]$menu.Items.Add('Ouvrir les journaux', $null, [System.EventHandler]{ Start-Process (Get-LogDir -Backend $backend) })
        $miAbout = $menu.Items.Add('À propos de Vigie', $null, [System.EventHandler]{ & $openRepo })
        $miAbout.ToolTipText = $repoUrl
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        [void]$menu.Items.Add('Quitter', $null, [System.EventHandler]{ & $stopServer; $icon.Visible = $false; $icon.Dispose(); [System.Windows.Forms.Application]::Exit() })

        # Couleur et hauteur des items : reglees ICI en un seul endroit, pour tous les
        # items d'un coup. Le libelle d'etat garde sa couleur attenuee (ce n'est pas un
        # ToolStripMenuItem). Hauteur facon Win11 : ~32 px avec la police 9,5.
        $itemPad = New-Object System.Windows.Forms.Padding(2, 6, 2, 6)
        foreach ($it in $menu.Items) {
            if ($it -is [System.Windows.Forms.ToolStripMenuItem]) {
                $it.ForeColor = $lite
                $it.Padding   = $itemPad
            }
        }
        $icon.ContextMenuStrip = $menu
        $icon.add_MouseDoubleClick({ & $openApp })

        & $startServer
        TLog "serveur ok"

        $poll = {
            try {
                [void](Invoke-RestMethod -Uri $healthUrl -TimeoutSec 5 -ErrorAction Stop)
                $state.EverUp   = $true
                $state.Starting = $false
                $app = 'ok'; $lbl = 'En marche'
            } catch {
                $elapsed = ([datetime]::UtcNow.Ticks - $state.StartTicks) / 1e7
                if ($state.Starting -and $elapsed -le $startupGrace) {
                    # Demarrage en cours (premier lancement OU redemarrage demande par
                    # l'utilisateur) : c'est une attente normale, pas une panne.
                    $app = 'warn';  $lbl = 'Démarrage…'
                } elseif ($state.Starting) {
                    $app = 'error'; $lbl = 'Échec de démarrage'
                } else {
                    $app = 'error'; $lbl = 'Arrêtée / injoignable'
                }
            }
            $miInfo.Text = "État : $lbl"
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
[void]$ps.AddScript($uiScript).AddArgument($backend).AddArgument($trayLog).AddArgument($RepoUrl).AddArgument($PSScriptRoot)
try { $ps.Invoke() } catch { TLog ("ERREUR Invoke: " + $_.Exception.ToString()) }
foreach ($er in $ps.Streams.Error) { TLog ("STREAM ERROR: " + $er.ToString()) }
try { $rs.Close() } catch { }
try { $mutex.ReleaseMutex() } catch { }
TLog "termine"
