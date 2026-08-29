<#
    console-ui.ps1 - LE MEME AFFICHAGE PARTOUT. Aucune dependance : chargeable par
    n'importe quel script, sous Windows PowerShell 5.1 comme sous PowerShell 7.

    POURQUOI CE FICHIER EXISTE. Chaque script avait invente sa mise en page : ici des
    fleches, la des tirets, ailleurs rien ; le vert voulait dire « fait » dans l'un et
    « en cours » dans l'autre. Le 28/08, une etape d'installation a ECHOUE et la ligne
    finale disait quand meme « Termine. » en vert -- l'utilisateur ne pouvait pas le
    voir. Un affichage incoherent n'est pas un defaut de style : c'est une information
    fausse.

    LE VOCABULAIRE, et rien d'autre :

      Write-Title    "Installation"        un bloc commence      (cyan, souligne)
      Write-Step     "PowerShell 7"        une etape commence    (blanc, prefixe ::)
      Write-Ok       "installe"            elle a reussi         (vert,   [ok])
      Write-Warn     "sans les droits"     elle passe, degradee  (jaune,  [!] )
      Write-Fail     "Windows a refuse"    elle a echoue         (rouge,  [X] )
      Write-Info     "version 7.4.6"       un fait, sans verdict (gris)
      Write-Detail   "chemin: C:\..."      un fait secondaire    (gris fonce, indente)
      Write-Outcome  -Failures 0           le verdict final      (voir plus bas)

    LA REGLE DE COULEUR, invariable : le vert ne sort QUE d'une reussite, le rouge QUE
    d'un echec. Aucun script ne peut finir en vert avec un echec derriere lui, parce que
    Write-Outcome compte les echecs au lieu de les croire sur parole.

    L'ENCODAGE. Ce fichier est en UTF-8 AVEC BOM : sans lui, Windows PowerShell 5.1 lit
    les accents comme du latin-1 et affiche « instal­lÃ© ». Les marqueurs restent en ASCII
    pur ([ok], [X]) : ils traversent toutes les consoles, y compris celles d'un poste ou
    la page de code n'a pas ete changee.
#>

# Compteur d'echecs du script en cours. Write-Fail l'incremente ; Write-Outcome le lit.
# C'est ce compteur qui empeche un verdict final complaisant.
# LES LIBELLES VIENNENT AVEC L'AFFICHAGE. Ces deux fichiers sont voisins : charger l'un
# donne l'autre, et aucun script n'a plus a y penser. C'est la seule dependance de ce
# fichier, et elle ne sort pas de son dossier.
$_i18nPath = Join-Path $PSScriptRoot 'i18n.ps1'
if (Test-Path -LiteralPath $_i18nPath) { . $_i18nPath }

$script:UiFailures = 0
$script:UiWarnings = 0

function Write-Title {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host ""
    Write-Host $Text -ForegroundColor Cyan
    Write-Host (New-Object string ([char]0x2500), ([Math]::Min($Text.Length, 78))) -ForegroundColor DarkCyan
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host ""
    Write-Host (":: " + $Text) -ForegroundColor White
}

<#
    UNE ETAPE QUI REUSSIT N'EST PAS UNE CONCLUSION.

    Le vert etait pose sur chaque etape reussie, et le lecteur ne savait plus ou regarder :
    « il y a des ok en vert et pas tous, on ne sait pas trop » (29/08). Une dizaine de
    lignes vertes au fil de l'installation, puis une verte de plus a la fin -- rien ne
    distinguait le resultat du chemin parcouru.

    LE VERT NE SORT PLUS QUE DE Write-Outcome. Une etape reussie garde sa marque, en gris :
    elle se repere a la lecture sans reclamer l'attention. Le rouge, lui, ne bouge pas --
    un echec doit sauter aux yeux ou qu'il soit.
#>
function Write-Ok      { param([Parameter(Mandatory)][string]$Text) Write-Host ("  [ok] " + $Text) -ForegroundColor Gray }
function Write-Info    { param([Parameter(Mandatory)][string]$Text) Write-Host ("       " + $Text) -ForegroundColor Gray }
function Write-Detail  { param([Parameter(Mandatory)][string]$Text) Write-Host ("       " + $Text) -ForegroundColor DarkGray }

function Write-Warn {
    param([Parameter(Mandatory)][string]$Text)
    $script:UiWarnings++
    Write-Host ("  [!]  " + $Text) -ForegroundColor Yellow
}

function Write-Fail {
    param([Parameter(Mandatory)][string]$Text)
    $script:UiFailures++
    Write-Host ("  [X]  " + $Text) -ForegroundColor Red
}

# Combien d'echecs ce script a-t-il affiches ? Sert a decider d'un code de retour sans
# tenir un second compteur a la main -- celui qu'on oublie de mettre a jour.
function Get-UiFailureCount { return $script:UiFailures }

<#
    LE VERDICT FINAL. On ne lui demande pas « dis que c'est bon », on lui donne les
    faits et il conclut. -Failures / -Warnings sont facultatifs : sans eux, il compte
    ce que Write-Fail et Write-Warn ont affiche.

    Trois issues, et une seule est verte :
      0 echec, 0 reserve  -> vert   « Termine. »
      0 echec, n reserves -> jaune  « Termine, avec n reserve(s). »
      n echecs            -> rouge  « ECHEC : n etape(s) n'ont pas abouti. »
#>
function Write-Outcome {
    param(
        [string]$What = 'Terminé',
        [Nullable[int]]$Failures = $null,
        [Nullable[int]]$Warnings = $null,
        # Ce qu'on conseille de faire ensuite. Une ligne, jamais un paragraphe.
        [string]$NextStep = ''
    )
    $f = if ($null -ne $Failures) { $Failures } else { $script:UiFailures }
    $w = if ($null -ne $Warnings) { $Warnings } else { $script:UiWarnings }

    # UN ENCART, PAS UNE LIGNE DE PLUS. Apres trente lignes qui defilent, une conclusion
    # doit se voir sans etre cherchee -- c'est la seule chose que l'on relit quand on
    # revient devant l'ecran.
    $text = if ($f -gt 0)    { "ÉCHEC : " + $f + " étape(s) n'ont pas abouti." }
             elseif ($w -gt 0) { $What + ", avec " + $w + " réserve(s)." }
             else              { $What + "." }
    $color = if ($f -gt 0) { 'Red' } elseif ($w -gt 0) { 'Yellow' } else { 'Green' }

    $width = $text.Length
    if ($NextStep -and $NextStep.Length -gt $width) { $width = $NextStep.Length }
    if ($width -gt 76) { $width = 76 }
    $rule = New-Object string ([char]0x2500), ($width + 2)

    Write-Host ""
    Write-Host ([char]0x250C + $rule + [char]0x2510) -ForegroundColor $color
    Write-Host ([char]0x2502 + ' ' + $text.PadRight($width) + ' ' + [char]0x2502) -ForegroundColor $color
    if ($NextStep) {
        Write-Host ([char]0x2502 + ' ' + $NextStep.PadRight($width) + ' ' + [char]0x2502) -ForegroundColor DarkGray
    }
    Write-Host ([char]0x2514 + $rule + [char]0x2518) -ForegroundColor $color
    Write-Host ""
}
