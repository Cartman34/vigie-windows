<#
    show-confirm.ps1 - LA fenetre « voici ce qui va se passer, tu continues ? ». Autonome.

    POURQUOI UN FICHIER A PART. Cette fenetre doit s'afficher AVANT la toute premiere
    elevation, c'est-a-dire a un moment ou PowerShell 7 n'est peut-etre pas encore installe
    -- c'est justement ce qu'on s'apprete a installer. Elle est donc ecrite pour tourner
    AUSSI sous Windows PowerShell 5.1, present sur toute machine Windows.

    Regle posee par l'utilisateur : « on peut se permettre une compatibilite sur la toute
    premiere fenetre de confirmation, et apres on ne fait que du PS 7 ». Ce fichier est la
    seule exception ; tout le reste du projet vise PS7 sans concession.

    ET UNE SEULE IMPLEMENTATION. `Show-ElevationRationale` (common.ps1) ne redessine pas
    cette fenetre : elle appelle ce script. Deux dessins de la meme boite auraient diverge
    des la premiere retouche.

    ENCODAGE : ce fichier est en UTF-8 AVEC BOM. Sans le BOM, PowerShell 5.1 lit un fichier
    UTF-8 comme du Windows-1252 et les accents deviennent illisibles. Avec, les deux
    versions le lisent correctement -- les accents ne se negocient pas (D41).

    Codes de retour : 0 = l'utilisateur continue ; 3 = il refuse (ou ferme la fenetre) ;
                      1 = aucune interface graphique disponible, rien n'a ete demande.
#>
param(
    # SCENARIO NOMME : le texte vit ICI, pas chez l'appelant.
    #
    # `setup.cmd` ne peut pas porter les libelles : un fichier .cmd se lit dans la page de
    # code OEM, ou les accents deviennent des symboles. Or les accents ne se negocient pas
    # (D41). L'appelant nomme donc un scenario, et ce script -- en UTF-8 avec BOM -- ecrit
    # les phrases.
    [ValidateSet('', 'installation')]
    [string] $Scenario = '',

    [string] $Title,
    [string] $Summary,

    # Une ligne par changement annonce. Separateur : « | » (un tableau ne traverse pas
    # une ligne de commande sans y laisser des plumes).
    [string] $Changes = '',

    # Nom de l'agent a l'origine de la demande, s'il y en a un.
    [string] $InitiatedBy = '',

    # Texte du bouton de gauche et du bouton d'action.
    [string] $OkText     = 'Continuer',
    [string] $CancelText = 'Annuler',

    # Note grise sous le contenu. Vide = pas de note.
    [string] $Note = "Si tu continues, Windows demandera ensuite l'autorisation administrateur.`nRien n'est modifié avant cette étape, et tu peux encore refuser.",

    # Fermeture automatique, en millisecondes. Sert UNIQUEMENT a verifier la mise en page
    # sans bloquer : la fenetre se ferme seule et le script rend 3 (donc « refus »).
    [int] $FermerApresMs = 0
)

$ErrorActionPreference = 'Stop'
$nl = [Environment]::NewLine

if ($Scenario -eq 'installation') {
    $Title   = "Installer Vigie sur cet ordinateur"
    $Summary = "Vigie va s'installer dans C:\Program Files\Sowapps\Vigie, s'ajouter au démarrage de VOTRE session, " +
               "puis se lancer. PowerShell 7 et le module Pode seront installés s'ils manquent."
    $Changes = "Copie du programme dans C:\Program Files\Sowapps\Vigie" +
               "|Tâche de démarrage pour votre compte uniquement" +
               "|Installation de PowerShell 7 pour toute la machine, s'il manque" +
               "|Aucun réglage de Windows Update n'est modifié à l'installation" +
               "|Rien n'est supprimé ailleurs sur la machine"
}
if (-not $Title -or -not $Summary) {
    Write-Host "Rien a afficher : precisez -Scenario, ou -Title et -Summary." -ForegroundColor Yellow
    exit 1
}
$puces = @()
if ($Changes) { $puces = @($Changes -split '\|' | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) }
$listeTexte = if ($puces.Count) { ($puces | ForEach-Object { "   - $_" }) -join $nl } else { '' }

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
} catch {
    Write-Host ""
    if ($InitiatedBy) { Write-Host ("Demandé par un agent automatisé : " + $InitiatedBy) -ForegroundColor Yellow }
    Write-Host $Title -ForegroundColor Cyan
    Write-Host $Summary
    if ($listeTexte) { Write-Host $listeTexte }
    Write-Host "Interface graphique indisponible : rien n'a été demandé." -ForegroundColor Yellow
    exit 1
}

$bg  = [System.Drawing.Color]::FromArgb(22, 27, 34)
$fg  = [System.Drawing.Color]::FromArgb(230, 237, 243)
$mut = [System.Drawing.Color]::FromArgb(139, 148, 158)
$acc = [System.Drawing.Color]::FromArgb(56, 139, 253)

$form                 = New-Object System.Windows.Forms.Form
$form.Text            = 'Vigie — autorisation requise'
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.TopMost         = $true
$form.BackColor       = $bg
$form.ForeColor       = $fg
$form.ClientSize      = New-Object System.Drawing.Size(580, 306)

# L'icone de Vigie plutot que celle de l'interpreteur : la fenetre doit s'annoncer comme
# venant de l'application, pas de ce qui l'execute.
try {
    $racine = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $ico = Join-Path $racine 'apps/backend-pode/assets/tray/ok.ico'
    if (Test-Path -LiteralPath $ico) { $form.Icon = New-Object System.Drawing.Icon($ico) }
} catch { }

$fTitre = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$fTexte = New-Object System.Drawing.Font('Segoe UI', 9.5)
$fNote  = New-Object System.Drawing.Font('Segoe UI', 9)
$fGras  = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)

$marge   = 24
$largeur = 532

# MISE EN PAGE MESUREE : chaque bloc prend la hauteur de son texte, et la fenetre s'ajuste.
# Des hauteurs fixes faisaient passer un resume de trois lignes SOUS la liste (vu le 27/08).
function Mesurer {
    param([string]$Texte, $Fonte)
    if (-not $Texte) { return 0 }
    $t = [System.Windows.Forms.TextRenderer]::MeasureText(
            $Texte, $Fonte,
            (New-Object System.Drawing.Size($largeur, 0)),
            ([System.Windows.Forms.TextFormatFlags]::WordBreak))
    return [int]$t.Height + 2
}

$controles = @()
$y = 20

if ($InitiatedBy) {
    $lblOrigine           = New-Object System.Windows.Forms.Label
    $lblOrigine.Text      = "Demandé par un agent automatisé : $InitiatedBy" + $nl + "Ce n'est pas toi qui as lancé cette action."
    $lblOrigine.Font      = $fGras
    $lblOrigine.ForeColor = [System.Drawing.Color]::FromArgb(210, 153, 34)
    $lblOrigine.BackColor = [System.Drawing.Color]::FromArgb(38, 34, 22)
    $lblOrigine.Padding   = New-Object System.Windows.Forms.Padding(10, 6, 10, 6)
    $h                    = (Mesurer -Texte $lblOrigine.Text -Fonte $fGras) + 12
    $lblOrigine.Location  = New-Object System.Drawing.Point($marge, $y)
    $lblOrigine.Size      = New-Object System.Drawing.Size($largeur, $h)
    $controles += $lblOrigine
    $y += $h + 16
}

$lblTitre           = New-Object System.Windows.Forms.Label
$lblTitre.Text      = $Title
$lblTitre.Font      = $fTitre
$lblTitre.ForeColor = $fg
$h                  = Mesurer -Texte $Title -Fonte $fTitre
$lblTitre.Location  = New-Object System.Drawing.Point($marge, $y)
$lblTitre.Size      = New-Object System.Drawing.Size($largeur, $h)
$controles += $lblTitre
$y += $h + 12

$lblResume           = New-Object System.Windows.Forms.Label
$lblResume.Text      = $Summary
$lblResume.Font      = $fTexte
$lblResume.ForeColor = $fg
$h                   = Mesurer -Texte $Summary -Fonte $fTexte
$lblResume.Location  = New-Object System.Drawing.Point($marge, $y)
$lblResume.Size      = New-Object System.Drawing.Size($largeur, $h)
$controles += $lblResume
$y += $h + 14

if ($listeTexte) {
    $lblListe           = New-Object System.Windows.Forms.Label
    $lblListe.Text      = $listeTexte
    $lblListe.Font      = $fTexte
    $lblListe.ForeColor = $fg
    $h                  = Mesurer -Texte $listeTexte -Fonte $fTexte
    $lblListe.Location  = New-Object System.Drawing.Point($marge, $y)
    $lblListe.Size      = New-Object System.Drawing.Size($largeur, $h)
    $controles += $lblListe
    $y += $h + 18
}

if ($Note) {
    $lblNote           = New-Object System.Windows.Forms.Label
    $lblNote.Text      = $Note
    $lblNote.Font      = $fNote
    $lblNote.ForeColor = $mut
    $h                 = Mesurer -Texte $Note -Fonte $fNote
    $lblNote.Location  = New-Object System.Drawing.Point($marge, $y)
    $lblNote.Size      = New-Object System.Drawing.Size($largeur, $h)
    $controles += $lblNote
    $y += $h + 18
}

$btnOk              = New-Object System.Windows.Forms.Button
$btnOk.Text         = $OkText
$btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
$btnOk.BackColor    = $acc
$btnOk.ForeColor    = [System.Drawing.Color]::White
$btnOk.FlatStyle    = 'Flat'
$btnOk.FlatAppearance.BorderSize = 0
$btnOk.Size         = New-Object System.Drawing.Size(124, 32)
$btnOk.Location     = New-Object System.Drawing.Point(432, $y)

$btnNon              = New-Object System.Windows.Forms.Button
$btnNon.Text         = $CancelText
$btnNon.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$btnNon.BackColor    = [System.Drawing.Color]::FromArgb(33, 38, 45)
$btnNon.ForeColor    = $fg
$btnNon.FlatStyle    = 'Flat'
$btnNon.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(68, 76, 86)
$btnNon.Size         = New-Object System.Drawing.Size(104, 32)
$btnNon.Location     = New-Object System.Drawing.Point(318, $y)

$controles += $btnOk
$controles += $btnNon
$form.Controls.AddRange($controles)
$form.AcceptButton = $btnOk
$form.CancelButton = $btnNon          # Echap et la croix ferment en REFUSANT
$form.ClientSize   = New-Object System.Drawing.Size(580, ($y + 32 + 20))

# Barre de titre sombre et coins arrondis quand la machine sait le faire. C'est du confort :
# une machine qui ne connait pas ces attributs affiche une fenetre normale, sans erreur.
try {
    $type = 'ChromeConfirm'
    if (-not ([System.Management.Automation.PSTypeName]$type).Type) {
        Add-Type -Name $type -Namespace Vigie -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int val, int size);
'@ -ErrorAction Stop
    }
    $vrai = 1
    [void][Vigie.ChromeConfirm]::DwmSetWindowAttribute($form.Handle, 20, [ref]$vrai, 4)   # barre sombre
    $rond = 2
    [void][Vigie.ChromeConfirm]::DwmSetWindowAttribute($form.Handle, 33, [ref]$rond, 4)   # coins arrondis
} catch { }

# Verification de mise en page sans blocage : la fenetre se ferme seule.
if ($FermerApresMs -gt 0) {
    $minuteur = New-Object System.Windows.Forms.Timer
    $minuteur.Interval = $FermerApresMs
    $minuteur.Add_Tick({ $minuteur.Stop(); $form.Close() })
    $minuteur.Start()
    $form.Add_Shown({
        Write-Host ("Hauteur de fenetre calculee : " + $form.ClientSize.Height + " px")
        foreach ($c in $form.Controls) {
            Write-Host ("  " + $c.GetType().Name.PadRight(7) + " y=" + $c.Top.ToString().PadLeft(4) +
                        "  h=" + $c.Height.ToString().PadLeft(3) + "  bas=" + ($c.Top + $c.Height))
        }
    })
}

$form.Add_Shown({ $form.Activate() })
$res = $form.ShowDialog()
$form.Dispose()
if ($res -eq [System.Windows.Forms.DialogResult]::OK) { exit 0 }
exit 3
