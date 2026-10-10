# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    show-confirm.ps1 -- THE window that says "here is what is about to happen, do you carry on?". Self-contained.

    Intent: never send a bare UAC prompt. Before anything is elevated or changed, somebody reads what will be
    touched and why, and can refuse without any system prompt appearing. The same window also serves to ANNOUNCE a
    result, where it asks nothing.

    Usage: it is called as a separate process, with KEYS and not texts (see further down), and it answers through
    its exit code: 0 = the user carries on; 3 = they refuse (or close the window); 1 = no graphical interface is
    available and nothing was asked; 4 = the third way out.

    WHY A SEPARATE FILE. This window must appear BEFORE the very first elevation, that is, at a moment when
    PowerShell 7 may not be installed yet -- it is precisely what we are about to install. So it is written to run
    under Windows PowerShell 5.1 as well, present on every Windows machine.

    A rule laid down by the owner: a compatibility concession is allowed on the very first confirmation window, and
    afterwards it is PS 7 only. This file is the sole exception; all the rest of the project targets PS7 without
    concession.

    AND ONE SINGLE IMPLEMENTATION. `Show-ElevationRationale` (common.ps1) does not redraw this window: it calls
    this script. Two drawings of the same box would have diverged at the first retouch.

    ENCODING: this file is UTF-8 WITH a BOM. Without the BOM, PowerShell 5.1 reads a UTF-8 file as Windows-1252 and
    the accents become unreadable. With it, both versions read it correctly -- accents are not negotiable (D41).
#>
param(
    # A NAMED SCENARIO: the text lives HERE, not in the caller.
    #
    # `setup.cmd` cannot carry the labels: a .cmd file is read in the OEM code page, where accents become symbols.
    # Yet accents are not negotiable (D41). So the caller names a scenario, and this script -- in UTF-8 with a BOM
    # -- writes the sentences.
    [ValidateSet('', 'installation', 'mise-a-jour', 'dossier', 'desinstallation')]
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

    # One line per announced change. The separator is a vertical bar (an array does not cross a command line without
    # leaving feathers behind).
    [string] $Changes = '',

    # The name of the agent behind the request, if there is one.
    [string] $InitiatedBy = '',

    # The text of the left-hand button and of the action button.
    [string] $OkText     = 'Continuer',
    [string] $CancelText = 'Annuler',

    <#
        A THIRD WAY OUT, when the question is not a binary one.

        "An operation is under way" does not call for yes or no: one can do nothing, wait for the end, or force it.
        Offering two buttons would force a choice between giving up and breaking -- and waiting, which is often the
        right answer, would not exist.

        Exit code 4, distinct from 0 (the main button) and 3 (a refusal).
    #>

    [string] $ThirdText = '',

    # A grey note under the content. Empty = no note.
    [string] $Note = "Windows demandera ensuite l'autorisation administrateur.`nRien n'est modifié avant cette étape.",

    # The text of the title bar. "Authorisation required" suits a request, not a window announcing a result.
    [string] $Caption = 'Vigie — autorisation requise',

    <#
        THE TECHNICAL DETAILS UNFOLD, THEY DO NOT IMPOSE THEMSELVES.

        A result window addresses somebody who wants to know whether it went well. Log paths and task names do not
        answer that question: they serve AFTERWARDS, when something is wrong. Displayed up front, they drown the
        message (reported on 29/08).

        So they live behind a Details toggle, folded by default. The window grows when it is opened, and nothing is
        lost for whoever is looking.
    #>

    [string] $Details = '',

    <#
        A PATH IS NOT RETYPED BY HAND.

        The log was announced as a RELATIVE path, under the server app folder, and so was useless: relative to
        what? It is now given in full, and above all it OPENS with one click. Somebody who unfolds the details is
        trying to read that file: giving them its path means asking them to do the work themselves.
    #>

    [string] $OpenPath = '',
    [string] $OpenText = 'Ouvrir le journal',

    <#
        THE TEXT DOES NOT CROSS THE COMMAND LINE.

        An accented text passed as an argument to ANOTHER process goes through the command line, and so through the
        code page of the moment: an accented word came back mangled (observed on 29/08). No file encoding can do
        anything about it -- the damage is done between the two processes.

        So we pass KEYS, and the window reads lang/fr.json itself: a key is pure ASCII, it crosses any code page
        without harm. The text never moves from its own file.
    #>


    <#
        FOR THE TEXT THAT CANNOT BE NAMED BY A KEY.

        Keys suit fixed texts. The elevation window, for its part, displays what the ACTION declares -- its impact,
        its use, its reversibility: built text, different every time, that no key designates.

        So it travels through a JSON file in UTF-8, of which only the PATH crosses the command line. A path is
        ASCII; the text undergoes no conversion at all.
    #>

    [string] $PayloadFile = '',

    [string] $TitleKey   = '',
    [string] $SummaryKey = '',
    [string] $DetailsKey = '',
    # The value that fills the {0} hole in the details text: a URL, a path. ASCII.
    [string] $DetailsArg = '',
    # The same for the summary: one version to another. ASCII as well.
    [string] $SummaryArg = '',

    # Automatic closing, in milliseconds. It serves ONLY to check the layout without blocking: the window closes by
    # itself and the script returns 3 (so, a refusal).
    [int] $CloseAfterMs = 0
)

$ErrorActionPreference = 'Stop'
# This file is isolated: it loads the common display itself, which also brings the labels (console-ui.ps1 and
# i18n.ps1 are its neighbours).
. (Join-Path $PSScriptRoot 'console-ui.ps1')

# The payload first: it is what carries the built text.
if ($PayloadFile -and (Test-Path -LiteralPath $PayloadFile)) {
    try {
        $charge = [System.IO.File]::ReadAllText($PayloadFile, (New-Object System.Text.UTF8Encoding($false))) | ConvertFrom-Json
        if ($charge.title)       { $Title       = "$($charge.title)" }
        if ($charge.summary)     { $Summary     = "$($charge.summary)" }
        if ($charge.changes)     { $Changes     = "$($charge.changes)" }
        if ($charge.initiatedBy) { $InitiatedBy = "$($charge.initiatedBy)" }
        if ($charge.scenario)    { $Scenario    = "$($charge.scenario)" }
    } catch { }
}

# The keys win over the texts: that is the safe road.
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
if ($Scenario -in @('installation', 'mise-a-jour')) {
    # THE TEXT IS THE PLAN: scripts/lib/install-plan.ps1 computes it from the machine and passes it by -PayloadFile.
    # Nothing is written here by hand, so the window cannot announce a gesture the installation will not make.
    $OkText = if ($Scenario -eq 'mise-a-jour') { Get-Label 'install-plan.bouton-maj' } else { Get-Label 'install-plan.bouton-installer' }
}
if ($Scenario -eq 'dossier') {
    # AN INSTALLATION CHOOSES ITS FOLDER FIRST: the gestures are announced afterwards, naming the folder retained.
    if (-not $InstallPath) { $InstallPath = Join-Path (Join-Path $env:ProgramFiles 'Sowapps') 'Vigie' }
    $Title     = Get-Label 'install-plan.dossier-titre'
    $Summary   = Get-Label 'install-plan.dossier-resume' $InstallPath
    $ThirdText = Get-Label 'install-plan.dossier-choisir'
    $Note      = ''
}
if (-not $Title -or -not $Summary) {
    Write-Host (Get-Label 'show-confirm.rien-afficher-precisez-scenario') -ForegroundColor Yellow
    exit 1
}
$bullets = @()
if ($Changes) { $bullets = @($Changes -split '\|' | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) }
$bulletText = if ($bullets.Count) { ($bullets | ForEach-Object { "   - $_" }) -join $nl } else { '' }

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
} catch {
    Write-Host ""
    if ($InitiatedBy) { Write-Host (Get-Label 'show-confirm.demande-par-un-agent' $InitiatedBy) -ForegroundColor Yellow }
    Write-Host $Title -ForegroundColor Cyan
    Write-Host $Summary
    if ($bulletText) { Write-Host $bulletText }
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

# Vigie's icon rather than the interpreter's: the window must announce itself as coming from the application, not
# from what runs it.
try {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    # THE ICON LIVES WITH THE CLIENT APP. This pointed at apps/backend-pode/assets/client/, a folder that has
    # never existed: the test failed in silence and the window kept the interpreter's icon.
    $ico = Join-Path $repoRoot 'apps/client/assets/ok.ico'
    if (Test-Path -LiteralPath $ico) { $form.Icon = New-Object System.Drawing.Icon($ico) }
} catch { }

$fontTitle = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$fontBody = New-Object System.Drawing.Font('Segoe UI', 9.5)
$fNote  = New-Object System.Drawing.Font('Segoe UI', 9)
$fGras  = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)

$marge   = 24
$width = 532

# A MEASURED LAYOUT: each block takes the height of its own text, and the window adjusts. Fixed heights sent a
# three-line summary UNDER the list (seen on 27/08).
<#
    A LABEL THAT SIZES ITSELF, and whose REAL height is then read.

    It replaces the pair "measure, then set a size": on a screen at 125 %, Windows enlarges the text after the
    measurement, the height that was set becomes too short, and the last line is clipped. A label in AutoSize takes
    what it needs.
#>
function New-WrappedLabel {
    param([string]$Text, $Font, $Colour, [int]$Top)
    $lbl           = New-Object System.Windows.Forms.Label
    $lbl.Text      = $Text
    $lbl.Font      = $Font
    $lbl.ForeColor = $Colour
    $lbl.AutoSize    = $true
    $lbl.MaximumSize = New-Object System.Drawing.Size($width, 0)
    $lbl.Location    = New-Object System.Drawing.Point($marge, $Top)
    return $lbl
}

function Measure-TextHeight {
    param([string]$Text, $Font)
    if (-not $Text) { return 0 }
    # AN EMPTY LINE TAKES UP SPACE, AND MeasureText DOES NOT COUNT IT. A text in paragraphs -- separated by a blank
    # line -- was therefore measured too short, and the label clipped its last line (observed on 29/08, a sentence
    # cut in two). We replace every empty line with a space: it then has the height of a line, which is what it
    # really occupies.
    $mesurable = $Text -replace '(?m)^\s*$', ' '
    $t = [System.Windows.Forms.TextRenderer]::MeasureText(
            $mesurable, $Font,
            (New-Object System.Drawing.Size($width, 0)),
            ([System.Windows.Forms.TextFormatFlags]::WordBreak))
    return [int]$t.Height + 4
}

$controles = @()
$y = 20

if ($InitiatedBy) {
    $lblOrigine           = New-Object System.Windows.Forms.Label
    $lblOrigine.Text      = "Demandé par un agent automatisé : $InitiatedBy" + $nl + "Cette action n'a pas été lancée par une personne."
    $lblOrigine.Font      = $fGras
    $lblOrigine.ForeColor = [System.Drawing.Color]::FromArgb(210, 153, 34)
    $lblOrigine.BackColor = [System.Drawing.Color]::FromArgb(38, 34, 22)
    $lblOrigine.Padding   = New-Object System.Windows.Forms.Padding(10, 6, 10, 6)
    $h                    = (Measure-TextHeight -Text $lblOrigine.Text -Font $fGras) + 12
    $lblOrigine.Location  = New-Object System.Drawing.Point($marge, $y)
    $lblOrigine.Size      = New-Object System.Drawing.Size($width, $h)
    $controles += $lblOrigine
    $y += $h + 16
}

$lblTitle = New-WrappedLabel -Text $Title -Font $fontTitle -Colour $fg -Top $y
$h = $lblTitle.PreferredSize.Height
$controles += $lblTitle
$y += $h + 12

$lblSummary = New-WrappedLabel -Text $Summary -Font $fontBody -Colour $fg -Top $y
$h = $lblSummary.PreferredSize.Height
$controles += $lblSummary
$y += $h + 14

if ($bulletText) {
    $lblListe = New-WrappedLabel -Text $bulletText -Font $fontBody -Colour $fg -Top $y
$h = $lblListe.PreferredSize.Height
$controles += $lblListe
    $y += $h + 18
}

# --- The details, folded ------------------------------------------------------
$lblDetails = $null
$lnkDetails = $null
$lnkOuvrir  = $null
$txtPath  = $null
if ($Details) {
    $detailText = ($Details -split '\|') -join [Environment]::NewLine

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

    $lblDetails = New-WrappedLabel -Text $detailText -Font $fNote -Colour $mut -Top $y
    $hDetails   = $lblDetails.PreferredSize.Height
    $lblDetails.Visible   = $false      # folded by default
    $controles += $lblDetails

    # A PATH MUST BE COPYABLE. A label cannot be selected: the path was displayed, and had to be retyped. A
    # read-only text box reads the same, and copies.
    if ($OpenPath) {
        $txtPath = New-Object System.Windows.Forms.TextBox
        $txtPath.Text       = $OpenPath
        $txtPath.Font       = $fNote
        $txtPath.ReadOnly   = $true
        $txtPath.BorderStyle = 'FixedSingle'
        $txtPath.BackColor  = [System.Drawing.Color]::FromArgb(33, 38, 45)
        $txtPath.ForeColor  = $mut
        $txtPath.Location   = New-Object System.Drawing.Point($marge, ($y + $hDetails + 8))
        $txtPath.Size       = New-Object System.Drawing.Size($width, 24)
        $txtPath.Visible    = $false
        $controles += $txtPath
    }

    # THE LINK LIVES WITH THE DETAILS: it appears and disappears with them.
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
    $lblNote = New-WrappedLabel -Text $Note -Font $fNote -Colour $mut -Top $y
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

# A RESULT WINDOW HAS NOTHING TO REFUSE. When the caller gives no cancel label, it is asking no question: it is
# announcing. The second button disappears, and the cross closes normally instead of meaning "no".
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
    $form.CancelButton = $btnNon      # Escape and the cross close by REFUSING
}
$form.ClientSize   = New-Object System.Drawing.Size(580, ($y + 32 + 20))

# FOLDING MOVES EVERYTHING THAT FOLLOWS. Showing the block without moving the rest would send it UNDER the
# buttons: the window grows by the block's exact height, and the controls placed after it go down as much.
if ($lnkDetails -and $lblDetails) {
    $lnkDetails.Add_LinkClicked({
        $ouvert = -not $lblDetails.Visible
        $lblDetails.Visible = $ouvert
        $hLien = 0
        if ($txtPath) { $txtPath.Visible = $ouvert; $hLien += 32 }
        if ($lnkOuvrir) { $lnkOuvrir.Visible = $ouvert; $hLien += 26 }
        $bloc   = $lblDetails.Height + 12 + $hLien
        $delta  = if ($ouvert) { $bloc } else { -$bloc }
        # "LOWER OR AT THE SAME LEVEL". The controls laid down AFTER the folded block begin at exactly the same
        # height as it, since it takes up no space while hidden. With "-gt" they did not move: the Close button
        # ended up UNDER the unfolded text, and so invisible (29/08).
        foreach ($c in $form.Controls) {
            if ($c -ne $lblDetails -and $c -ne $lnkOuvrir -and $c -ne $txtPath -and
                $c.Top -ge $lblDetails.Top) {
                $c.Top = $c.Top + $delta
            }
        }
        $form.ClientSize = New-Object System.Drawing.Size($form.ClientSize.Width, ($form.ClientSize.Height + $delta))
        $lnkDetails.Text = if ($ouvert) { [char]0x25BE + ' Masquer les détails' }
                           else            { [char]0x25B8 + ' Détails' }
    })
}

# A dark title bar and rounded corners when the machine knows how. This is comfort: a machine that does not know
# these attributes shows an ordinary window, without an error.
try {
    $type = 'ChromeConfirm'
    if (-not ([System.Management.Automation.PSTypeName]$type).Type) {
        Add-Type -Name $type -Namespace Vigie -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int val, int size);
'@ -ErrorAction Stop
    }
    $vrai = 1
    [void][Vigie.ChromeConfirm]::DwmSetWindowAttribute($form.Handle, 20, [ref]$vrai, 4)   # a dark bar
    $rond = 2
    [void][Vigie.ChromeConfirm]::DwmSetWindowAttribute($form.Handle, 33, [ref]$rond, 4)   # rounded corners
} catch { }

# A layout check without blocking: the window closes by itself.
if ($CloseAfterMs -gt 0) {
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $CloseAfterMs
    $timer.Add_Tick({ $timer.Stop(); $form.Close() })
    $timer.Start()
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
if ($res -eq [System.Windows.Forms.DialogResult]::Retry -and $Scenario -eq 'dossier') {
    $choisi = $null
    try {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description  = 'Dossier ou installer Vigie'
        $dlg.SelectedPath = $InstallPath
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $choisi = "$($dlg.SelectedPath)" }
    } catch { }
    <#
        CANCELLING THE CHOICE IS NOT CANCELLING THE INSTALLATION.

        Closing the folder picker returned the same code as a refusal, and setup.cmd aborted
        everything: you meant to keep the default, you quit instead. So we keep the folder we
        proposed and carry on -- the announcement has been read and accepted already.
    #>
    if (-not $choisi) { $choisi = $InstallPath }
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
# 4 = the third way out. Distinct from a refusal: waiting is not cancelling, and the caller must be able to tell
# the difference.
if ($res -eq [System.Windows.Forms.DialogResult]::Retry) { exit 4 }
exit 3
