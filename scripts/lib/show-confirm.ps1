# @author Florent HAZARD <f.hazard@sowapps.com>
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
    [ValidateSet('', 'installation', 'desinstallation')]
    [string] $Scenario = '',

    [string] $Title,
    [string] $Summary,

    <#
        WHERE WE PROPOSE TO INSTALL.

        The window does not merely announce it: it lets another folder be chosen, because this
        is the last moment where the question means anything -- afterwards the elevation has
        happened and the console is gone.
    #>
    [string] $InstallPath = '',

    <#
        WHERE TO WRITE THE FOLDER THAT WAS RETAINED. An exit code carries no path.

        NOT ON STANDARD OUTPUT: this window already writes its layout checks there, and the
        caller would have read "Button y= 276" instead of the folder (measured on 03/09). A
        file is not polluted by whatever crosses the console.
    #>
    [string] $OutFile = '',

    # Une ligne par changement annonce. Separateur : « | » (un tableau ne traverse pas
    # une ligne de commande sans y laisser des plumes).
    [string] $Changes = '',

    # Nom de l'agent a l'origine de la demande, s'il y en a un.
    [string] $InitiatedBy = '',

    # Texte du bouton de gauche et du bouton d'action.
    [string] $OkText     = 'Continuer',
    [string] $CancelText = 'Annuler',

    <#
        UNE TROISIEME ISSUE, quand la question n'est pas binaire.

        « Une operation est en cours » n'appelle pas oui/non : on peut ne rien faire,
        attendre la fin, ou forcer. Proposer deux boutons obligerait a choisir entre
        renoncer et casser -- et l'attente, qui est souvent la bonne reponse, n'existerait
        pas.

        Code de retour 4, distinct du 0 (bouton principal) et du 3 (refus).
    #>
    [string] $ThirdText = '',

    # Note grise sous le contenu. Vide = pas de note.
    [string] $Note = "Si tu continues, Windows demandera ensuite l'autorisation administrateur.`nRien n'est modifié avant cette étape, et tu peux encore refuser.",

    # Le texte de la barre de titre. « autorisation requise » convient a une demande,
    # pas a une fenetre qui annonce un resultat.
    [string] $Caption = 'Vigie — autorisation requise',

    <#
        LES DETAILS TECHNIQUES SE DEPLIENT, ILS NE S'IMPOSENT PAS.

        Une fenetre de resultat s'adresse a quelqu'un qui veut savoir si c'est bon. Les
        chemins de journaux et les noms de taches ne repondent pas a cette question : ils
        servent APRES, quand quelque chose cloche. Affiches d'entree, ils noient le
        message (signale le 29/08).

        Ils vivent donc derriere « Détails », replie par defaut. La fenetre grandit quand
        on l'ouvre, et rien n'est perdu pour qui cherche.
    #>
    [string] $Details = '',

    <#
        UN CHEMIN NE SE RECOPIE PAS A LA MAIN.

        Le journal etait annonce en chemin RELATIF -- « apps\backend-pode\var\log\... » --
        donc inutilisable : relatif a quoi ? Il est desormais donne en entier, et surtout
        il s'OUVRE d'un clic. Quelqu'un qui deplie les details cherche a lire ce fichier :
        lui donner son chemin, c'est lui demander de faire le travail lui-meme.
    #>
    [string] $OpenPath = '',
    [string] $OpenText = 'Ouvrir le journal',

    <#
        LE TEXTE NE TRAVERSE PAS LA LIGNE DE COMMANDE.

        Un texte accentue passe en argument d'un AUTRE processus, donc par la ligne de
        commande, donc par la page de code du moment : « sécurité » y devient « sÎcuritÎ »
        (constate le 29/08). Aucun encodage de fichier n'y peut rien -- le mal est fait
        entre les deux processus.

        On passe donc des CLES, et la fenetre lit lang/fr.json elle-meme : une cle est de
        l'ASCII pur, elle traverse n'importe quelle page de code sans dommage. Le texte,
        lui, ne bouge jamais de son fichier.
    #>
    <#
        POUR LE TEXTE QU'ON NE PEUT PAS NOMMER PAR UNE CLE.

        Les cles conviennent aux textes fixes. La fenetre d'elevation, elle, affiche ce
        que l'ACTION declare -- son impact, son usage, sa reversibilite : du texte
        construit, different a chaque fois, qu'aucune cle ne designe.

        Il passe donc par un fichier JSON en UTF-8, dont seul le CHEMIN traverse la ligne
        de commande. Un chemin est de l'ASCII ; le texte, lui, ne subit aucune conversion.
    #>
    [string] $PayloadFile = '',

    [string] $TitleKey   = '',
    [string] $SummaryKey = '',
    [string] $DetailsKey = '',
    # La valeur qui remplit le trou {0} du texte des details : une URL, un chemin. ASCII.
    [string] $DetailsArg = '',
    # Idem pour le resume : « v0.1.31 vers v0.1.32 ». ASCII lui aussi.
    [string] $SummaryArg = '',

    # Fermeture automatique, en millisecondes. Sert UNIQUEMENT a verifier la mise en page
    # sans bloquer : la fenetre se ferme seule et le script rend 3 (donc « refus »).
    [int] $FermerApresMs = 0
)

$ErrorActionPreference = 'Stop'
# Ce fichier est isole : il charge lui-meme l'affichage commun, qui apporte aussi
# les libelles (console-ui.ps1 et i18n.ps1 sont voisins).
. (Join-Path $PSScriptRoot 'console-ui.ps1')

# La charge utile d'abord : c'est elle qui porte le texte construit.
if ($PayloadFile -and (Test-Path -LiteralPath $PayloadFile)) {
    try {
        $charge = [System.IO.File]::ReadAllText($PayloadFile, (New-Object System.Text.UTF8Encoding($false))) | ConvertFrom-Json
        if ($charge.title)       { $Title       = "$($charge.title)" }
        if ($charge.summary)     { $Summary     = "$($charge.summary)" }
        if ($charge.changes)     { $Changes     = "$($charge.changes)" }
        if ($charge.initiatedBy) { $InitiatedBy = "$($charge.initiatedBy)" }
    } catch { }
}

# Les cles l'emportent sur les textes : c'est la voie sure.
if ($TitleKey)   { $Title   = Get-Label $TitleKey }
if ($SummaryKey) { $Summary = if ($SummaryArg) { Get-Label $SummaryKey $SummaryArg } else { Get-Label $SummaryKey } }
if ($DetailsKey) { $Details = if ($DetailsArg) { Get-Label $DetailsKey $DetailsArg } else { Get-Label $DetailsKey } }

$nl = [Environment]::NewLine

if ($Scenario -eq 'desinstallation') {
    $Title   = "Retirer Vigie de cet ordinateur"
    # WE NAME WHAT NOBODY EXPECTS. "Uninstall" suggests a program leaving; here the settings
    # and history of EVERY account leave with it. Saying so after the elevation would be
    # saying it too late.
    $Summary = "Vigie va etre entierement retiree : ses taches de demarrage, son compte de service et son " +
               "dossier d'installation. Les donnees de Vigie de TOUS les comptes de cet ordinateur seront " +
               "supprimees. PowerShell 7 et le module Pode, eux, restent en place."
    $Changes = "Le verrou pose sur Windows Update est leve" +
               "|Suppression des taches de demarrage de Vigie" +
               "|Suppression du compte de service et de son profil" +
               "|Suppression du dossier d'installation" +
               "|Suppression des donnees de Vigie de TOUS les comptes"
    $OkText  = 'Desinstaller'
    $CancelText = 'Quitter'
}
if ($Scenario -eq 'installation') {
    if (-not $InstallPath) { $InstallPath = (Join-Path $env:ProgramFiles 'Sowapps\Vigie') }
    $Title   = "Installer Vigie sur cet ordinateur"
    $Summary = "Vigie va s'installer dans " + $InstallPath + ", s'ajouter au démarrage de VOTRE session, " +
               "puis se lancer. PowerShell 7 et le module Pode seront installés s'ils manquent."
    $ThirdText = 'Choisir un autre dossier…'
    $Changes = "Copie du programme dans " + $InstallPath +
               "|Tâche de démarrage pour votre compte uniquement" +
               "|Installation de PowerShell 7 pour toute la machine, s'il manque" +
               "|Aucun réglage de Windows Update n'est modifié à l'installation" +
               "|Rien n'est supprimé ailleurs sur la machine"
}
if (-not $Title -or -not $Summary) {
    Write-Host (Get-Label 'show-confirm.rien-afficher-precisez-scenario') -ForegroundColor Yellow
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
    if ($InitiatedBy) { Write-Host (Get-Label 'show-confirm.demande-par-un-agent' $InitiatedBy) -ForegroundColor Yellow }
    Write-Host $Title -ForegroundColor Cyan
    Write-Host $Summary
    if ($listeTexte) { Write-Host $listeTexte }
    Write-Host (Get-Label 'show-confirm.interface-graphique-indisponible-rien') -ForegroundColor Yellow
    exit 1
}

$bg  = [System.Drawing.Color]::FromArgb(22, 27, 34)
$fg  = [System.Drawing.Color]::FromArgb(230, 237, 243)
$mut = [System.Drawing.Color]::FromArgb(139, 148, 158)
$acc = [System.Drawing.Color]::FromArgb(56, 139, 253)

$form                 = New-Object System.Windows.Forms.Form
$form.Text            = $Caption
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
$width = 532

# MISE EN PAGE MESUREE : chaque bloc prend la hauteur de son texte, et la fenetre s'ajuste.
# Des hauteurs fixes faisaient passer un resume de trois lignes SOUS la liste (vu le 27/08).
<#
    UN LIBELLE QUI SE DIMENSIONNE SEUL, et dont on lit la hauteur REELLE.

    Remplace le couple « mesurer puis poser une taille » : sur un ecran a 125 %, Windows
    agrandit le texte apres la mesure, la hauteur posee devient trop courte, et la
    derniere ligne est rognee. Un libelle en AutoSize prend ce qu'il lui faut.
#>
function Ajouter-Libelle {
    param([string]$Texte, $Fonte, $Couleur, [int]$Haut)
    $lbl           = New-Object System.Windows.Forms.Label
    $lbl.Text      = $Texte
    $lbl.Font      = $Fonte
    $lbl.ForeColor = $Couleur
    $lbl.AutoSize    = $true
    $lbl.MaximumSize = New-Object System.Drawing.Size($width, 0)
    $lbl.Location    = New-Object System.Drawing.Point($marge, $Haut)
    return $lbl
}

function Mesurer {
    param([string]$Texte, $Fonte)
    if (-not $Texte) { return 0 }
    # UNE LIGNE VIDE OCCUPE DE LA PLACE, ET MeasureText NE LA COMPTE PAS. Un texte en
    # paragraphes -- separes par une ligne blanche -- etait donc mesure trop court, et le
    # libelle rognait sa derniere ligne (constate le 29/08 : « Le déroulé complet de cette
    # installation est conservé ici : » coupe en deux). On remplace chaque ligne vide par
    # une espace : elle a alors la hauteur d'une ligne, ce qu'elle occupe reellement.
    $mesurable = $Texte -replace '(?m)^\s*$', ' '
    $t = [System.Windows.Forms.TextRenderer]::MeasureText(
            $mesurable, $Fonte,
            (New-Object System.Drawing.Size($width, 0)),
            ([System.Windows.Forms.TextFormatFlags]::WordBreak))
    return [int]$t.Height + 4
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
    $lblOrigine.Size      = New-Object System.Drawing.Size($width, $h)
    $controles += $lblOrigine
    $y += $h + 16
}

$lblTitre = Ajouter-Libelle -Texte $Title -Fonte $fTitre -Couleur $fg -Haut $y
$h = $lblTitre.PreferredSize.Height
$controles += $lblTitre
$y += $h + 12

$lblResume = Ajouter-Libelle -Texte $Summary -Fonte $fTexte -Couleur $fg -Haut $y
$h = $lblResume.PreferredSize.Height
$controles += $lblResume
$y += $h + 14

if ($listeTexte) {
    $lblListe = Ajouter-Libelle -Texte $listeTexte -Fonte $fTexte -Couleur $fg -Haut $y
$h = $lblListe.PreferredSize.Height
$controles += $lblListe
    $y += $h + 18
}

# --- Les details, replies ---------------------------------------------------------------
$lblDetails = $null
$lnkDetails = $null
$lnkOuvrir  = $null
$txtChemin  = $null
if ($Details) {
    $detailTexte = ($Details -split '\|') -join [Environment]::NewLine

    $lnkDetails           = New-Object System.Windows.Forms.LinkLabel
    $lnkDetails.Text      = ([char]0x25B8 + ' Détails')
    $lnkDetails.Font      = $fNote
    $lnkDetails.LinkColor = [System.Drawing.Color]::FromArgb(88, 166, 255)
    $lnkDetails.ActiveLinkColor = [System.Drawing.Color]::FromArgb(121, 192, 255)
    $lnkDetails.LinkBehavior = 'NeverUnderline'
    $lnkDetails.Location  = New-Object System.Drawing.Point($marge, $y)
    $lnkDetails.AutoSize  = $true
    $controles += $lnkDetails
    $y += 26

    $lblDetails = Ajouter-Libelle -Texte $detailTexte -Fonte $fNote -Couleur $mut -Haut $y
    $hDetails   = $lblDetails.PreferredSize.Height
    $lblDetails.Visible   = $false      # replie par defaut
    $controles += $lblDetails

    # UN CHEMIN DOIT POUVOIR SE COPIER. Un libelle ne se selectionne pas : le chemin
    # s'affichait, et il fallait le retaper. Une zone de texte en lecture seule se lit
    # pareil, et se copie.
    if ($OpenPath) {
        $txtChemin = New-Object System.Windows.Forms.TextBox
        $txtChemin.Text       = $OpenPath
        $txtChemin.Font       = $fNote
        $txtChemin.ReadOnly   = $true
        $txtChemin.BorderStyle = 'FixedSingle'
        $txtChemin.BackColor  = [System.Drawing.Color]::FromArgb(33, 38, 45)
        $txtChemin.ForeColor  = $mut
        $txtChemin.Location   = New-Object System.Drawing.Point($marge, ($y + $hDetails + 8))
        $txtChemin.Size       = New-Object System.Drawing.Size($width, 24)
        $txtChemin.Visible    = $false
        $controles += $txtChemin
    }

    # LE LIEN VIT AVEC LES DETAILS : il apparait et disparait avec eux.
    if ($OpenPath) {
        $lnkOuvrir           = New-Object System.Windows.Forms.LinkLabel
        $lnkOuvrir.Text      = ($OpenText + '  ' + [char]0x2197)
        $lnkOuvrir.Font      = $fNote
        $lnkOuvrir.LinkColor = [System.Drawing.Color]::FromArgb(88, 166, 255)
        $lnkOuvrir.ActiveLinkColor = [System.Drawing.Color]::FromArgb(121, 192, 255)
        $lnkOuvrir.LinkBehavior = 'NeverUnderline'
        $lnkOuvrir.Location  = New-Object System.Drawing.Point($marge, ($y + $hDetails + 38))
        $lnkOuvrir.AutoSize  = $true
        $lnkOuvrir.Visible   = $false
        $lnkOuvrir.Tag       = $OpenPath
        $lnkOuvrir.Add_LinkClicked({
            try { Start-Process -FilePath ([string]$this.Tag) } catch { }
        })
        $controles += $lnkOuvrir
    }
}

if ($Note) {
    $lblNote = Ajouter-Libelle -Texte $Note -Fonte $fNote -Couleur $mut -Haut $y
$h = $lblNote.PreferredSize.Height
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

# UNE FENETRE DE RESULTAT N'A RIEN A REFUSER. Quand l'appelant ne donne pas de libelle
# d'annulation, il ne pose pas de question : il annonce. Le second bouton disparait, et
# la croix ferme normalement au lieu de valoir « non ».
$noRefusal = [string]::IsNullOrWhiteSpace($CancelText)

$btnTiers = $null
if ($ThirdText) {
    $btnTiers              = New-Object System.Windows.Forms.Button
    $btnTiers.Text         = $ThirdText
    $btnTiers.DialogResult = [System.Windows.Forms.DialogResult]::Retry
    $btnTiers.BackColor    = [System.Drawing.Color]::FromArgb(33, 38, 45)
    $btnTiers.ForeColor    = $fg
    $btnTiers.FlatStyle    = 'Flat'
    $btnTiers.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(68, 76, 86)
    $btnTiers.AutoSize     = $true
    $btnTiers.Location     = New-Object System.Drawing.Point(20, $y)
    $controles += $btnTiers
}

$controles += $btnOk
if (-not $noRefusal) { $controles += $btnNon }
$form.Controls.AddRange($controles)
$form.AcceptButton = $btnOk
if ($noRefusal) {
    $btnOk.Location = New-Object System.Drawing.Point(432, $y)
    $form.CancelButton = $btnOk
} else {
    $form.CancelButton = $btnNon      # Echap et la croix ferment en REFUSANT
}
$form.ClientSize   = New-Object System.Drawing.Size(580, ($y + 32 + 20))

# LE PLIAGE DEPLACE TOUT CE QUI SUIT. Montrer le bloc sans bouger le reste le ferait
# passer SOUS les boutons : la fenetre grandit de la hauteur exacte du bloc, et les
# controles places apres lui descendent d'autant.
if ($lnkDetails -and $lblDetails) {
    $lnkDetails.Add_LinkClicked({
        $ouvert = -not $lblDetails.Visible
        $lblDetails.Visible = $ouvert
        $hLien = 0
        if ($txtChemin) { $txtChemin.Visible = $ouvert; $hLien += 32 }
        if ($lnkOuvrir) { $lnkOuvrir.Visible = $ouvert; $hLien += 26 }
        $bloc   = $lblDetails.Height + 12 + $hLien
        $delta  = if ($ouvert) { $bloc } else { -$bloc }
        # « PLUS BAS OU AU MEME NIVEAU ». Les controles poses APRES le bloc replie
        # commencent exactement a la meme hauteur que lui, puisqu'il ne prend aucune
        # place tant qu'il est cache. Avec « -gt » ils ne bougeaient pas : le bouton
        # Fermer se retrouvait SOUS le texte deplie, donc invisible (29/08).
        foreach ($c in $form.Controls) {
            if ($c -ne $lblDetails -and $c -ne $lnkOuvrir -and $c -ne $txtChemin -and
                $c.Top -ge $lblDetails.Top) {
                $c.Top = $c.Top + $delta
            }
        }
        $form.ClientSize = New-Object System.Drawing.Size($form.ClientSize.Width, ($form.ClientSize.Height + $delta))
        $lnkDetails.Text = if ($ouvert) { [char]0x25BE + ' Masquer les détails' }
                           else            { [char]0x25B8 + ' Détails' }
    })
}

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
        Write-Host (Get-Label 'show-confirm.hauteur-de-fenetre-calculee' $form.ClientSize.Height)
        foreach ($c in $form.Controls) {
            Write-Host (Get-Label 'show-confirm.bas' $c.GetType().Name.PadRight(7) $c.Top.ToString().PadLeft(4) $c.Height.ToString().PadLeft(3) $c.Top $c.Height)
        }
    })
}

$form.Add_Shown({ $form.Activate() })
$res = $form.ShowDialog()
$form.Dispose()
<#
    THE CHOSEN FOLDER GOES BACK THROUGH A FILE.

    An exit code says yes or no, never "D:\Outils\Vigie". The caller passes -OutFile and reads
    it back. Nothing is written outside the installation scenario: elsewhere the window stays
    as silent as before.
#>
if ($res -eq [System.Windows.Forms.DialogResult]::Retry -and $Scenario -eq 'installation') {
    $choisi = $null
    try {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description  = 'Dossier ou installer Vigie'
        $dlg.SelectedPath = $InstallPath
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $choisi = "$($dlg.SelectedPath)" }
    } catch { }
    # NOTHING CHOSEN = NOTHING DECIDED: we do not take a cancelled dialog for an agreement.
    if (-not $choisi) { exit 3 }
    # THE FOLDER IS THE ONE WE ANNOUNCE, not one we guessed: the product name is appended only
    # when the chosen folder does not already carry it.
    if ((Split-Path $choisi -Leaf) -ine 'Vigie') { $choisi = Join-Path $choisi 'Vigie' }
    if ($OutFile) { [IO.File]::WriteAllText($OutFile, $choisi, (New-Object Text.UTF8Encoding($false))) }
    exit 0
}
if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
    if ($OutFile -and $InstallPath) { [IO.File]::WriteAllText($OutFile, $InstallPath, (New-Object Text.UTF8Encoding($false))) }
    exit 0
}
# 4 = la troisieme issue. Distincte du refus : « attendre » n'est pas « annuler », et
# l'appelant doit pouvoir faire la difference.
if ($res -eq [System.Windows.Forms.DialogResult]::Retry) { exit 4 }
exit 3
