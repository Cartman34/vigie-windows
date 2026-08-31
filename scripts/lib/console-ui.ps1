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
                                             et la precedente conclut, en couleur
      Write-Ok       "installe"            un fait, reussi       (gris, sans marqueur)
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

<#
    CE QU'ON ECRIT SORT EN UTF-8, MEME REDIRIGE DANS UN FICHIER.

    Un script lance par le veilleur voit sa sortie redirigee vers un journal. Ce que
    Windows y ecrit suit [Console]::OutputEncoding, qui vaut la page de code du systeme
    (1252 ici) : les accents partaient donc en latin-1, et la carte affichait « La
    r?cup?ration n'a pas rendu de dossier utilisable » (constate le 31/08). Le journal
    n'etait pas relisible non plus.

    C'est pose ICI parce que tout ce qui s'affiche dans ce depot passe par ce fichier :
    une seule ligne, et aucun script n'a plus a y penser.
#>
try {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Text.UTF8Encoding]::new($false)
} catch { }

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

<#
    CHAQUE ETAPE DIT COMMENT ELLE FINIT.

    Une etape s'ouvrait, deroulait ses lignes, et la suivante commencait : pour savoir si
    elle avait abouti, il fallait relire ses lignes une par une et decider soi-meme. La
    conclusion n'existait qu'a la toute fin, pour le script entier.

    Desormais toute etape se referme par une DERNIERE LIGNE COLOREE qui dit son sort. Elle
    n'est pas ecrite par l'appelant : elle se DEDUIT de ce qui s'est passe entre son
    ouverture et sa fermeture -- rouge s'il y a eu un echec, jaune s'il y a eu une reserve,
    vert sinon. Un script ne peut donc pas conclure une etape en vert alors qu'elle a
    echoue, pas plus qu'il ne le pouvait pour le verdict final.

    Une etape se ferme toute seule : quand la suivante s'ouvre, ou quand le verdict tombe.
#>
$script:UiStepText = $null
$script:UiStepFailures = 0
$script:UiStepWarnings = 0

function Close-UiStep {
    if ($null -eq $script:UiStepText) { return }
    $f = $script:UiFailures - $script:UiStepFailures
    $w = $script:UiWarnings - $script:UiStepWarnings
    $texte = if ($f -gt 0)    { $script:UiStepText + " : échec." }
             elseif ($w -gt 0) { $script:UiStepText + " : fait, avec " + $w + " réserve(s)." }
             else              { $script:UiStepText + " : fait." }
    $couleur = if ($f -gt 0) { 'Red' } elseif ($w -gt 0) { 'Yellow' } else { 'Green' }
    Write-Host ("       " + $texte) -ForegroundColor $couleur
    $script:UiStepText = $null
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Text)
    Close-UiStep
    Write-Host ""
    Write-Host (":: " + $Text) -ForegroundColor White
    $script:UiStepText = $Text
    $script:UiStepFailures = $script:UiFailures
    $script:UiStepWarnings = $script:UiWarnings
}

<#
    UN SUCCES INTERMEDIAIRE N'EST PAS UNE CONCLUSION.

    Le vert etait pose sur chaque reussite, et le lecteur ne savait plus ou regarder : « il
    y a des ok en vert et pas tous, on ne sait pas trop » (29/08). Le marqueur « [ok] » a
    suivi le meme chemin : il decorait des faits sans jamais dire ou en etait l'etape.

    Il n'y a plus de marqueur. Un succes intermediaire est une ligne grise comme les
    autres faits ; ce qui conclut, c'est la derniere ligne de l'etape, coloree, et le
    verdict final. Le rouge et le jaune gardent les leurs -- un echec doit sauter aux yeux
    ou qu'il soit, et « [X] » est ce que relit le serveur pour dire POURQUOI une operation
    a echoue.
#>
function Write-Ok      { param([Parameter(Mandatory)][string]$Text) Write-Host ("       " + $Text) -ForegroundColor Gray }
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
# Combien d'echecs et de reserves ce script a-t-il affiches ? Sert a decider d'un code de
# retour, et a titrer la fenetre de fin, sans tenir un second compteur a la main -- celui
# qu'on oublie de mettre a jour.
#
# Get-UiWarningCount avait ete SUPPRIMEE comme code mort, puis reutilisee une heure plus
# tard par l'installation : « le terme n'est pas reconnu », en toute fin de parcours,
# apres que tout le reste avait reussi. Supprimer une fonction publique n'est pas gratuit.
function Get-UiFailureCount { return $script:UiFailures }
function Get-UiWarningCount { return $script:UiWarnings }

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
    # L'ETAPE EN COURS SE FERME AVANT LE VERDICT : sinon la derniere de toutes n'aurait
    # jamais dit comment elle finissait.
    Close-UiStep
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
