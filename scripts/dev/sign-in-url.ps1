<#
    SIGN-IN-URL : UNE ADRESSE D'OUVERTURE, A COLLER DANS UN VRAI NAVIGATEUR.

    A QUOI CA SERT. Regarder et deboguer Vigie dans son navigateur habituel -- outils de
    developpement, console, reseau -- plutot que dans la fenetre de l'app cliente. Ouvrir
    l'adresse du panneau a la main fonctionne, mais le serveur ne sait pas QUI regarde :
    « vous » n'apparait sur personne et aucune action ne sait qui la demande.

    CE QUE RENVOIE CE SCRIPT. Une adresse a USAGE UNIQUE, valable 30 secondes. Le serveur
    l'echange contre une session, puis renvoie le navigateur sur l'adresse principale --
    l'adresse d'ouverture ne reste donc ni dans la barre d'adresse, ni dans un signet.

    LA SESSION, ELLE, NE PERIME PAS. C'est le partage voulu : ce qui circule est jetable,
    ce qui reste ne l'est pas. On remet le pied a l'etrier une fois, et le navigateur
    continue d'etre identifie.

    POUR SOI, ET SEULEMENT POUR SOI. Le secret qui prouve l'identite vit dans le profil du
    compte, avec une ACL explicite. Pour ouvrir une session au nom d'un autre compte, il
    faut lancer ce script DANS SA session.

    STAGE DEV UNIQUEMENT. Ouvrir le panneau dans un navigateur separe est un geste de
    developpement : on regarde la console, le reseau, on rafraichit cinquante fois. En
    stage prod, Vigie s'ouvre par son icone, et une seconde facon d'obtenir une session
    n'y a rien a faire.

    Ce refus dit une INTENTION, il ne tient pas une frontiere : ce qui protege vraiment la
    session est le secret du compte, illisible par les autres. Le stage est DECLARE
    (machine.psd1), jamais deduit.

    Codes de retour : 0 = adresse rendue ; 2 = serveur muet, ou secret illisible ;
                      3 = stage prod, ce script n'y a pas sa place.
#>
[CmdletBinding()]
param(
    # -Open : ouvrir directement dans le navigateur par defaut, au lieu d'afficher.
    [switch] $Open,
    [int] $Port = 0
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$backend  = Join-Path $repoRoot 'apps/backend-pode'
. (Join-Path $backend 'lib/common.ps1')

<#
    ON DIT OU ON EN EST, A CHAQUE ETAPE.

    Le script ne disait rien avant d'avoir fini : quand il ne rendait pas la main, il n'y
    avait aucun moyen de savoir OU -- lecture du secret, appel au serveur, ou attente d'une
    reponse qui ne venait pas. Un outil muet qui tourne longtemps est un outil qu'on ne
    peut pas deboguer.
#>
Write-Step (Get-Label 'sign-in-url.etape-stage')
$stage = Get-DeclaredStage -Backend $backend
if ("$stage" -ne 'dev') {
    Write-Fail (Get-Label 'sign-in-url.stage-prod' (Get-StageLabel -Stage $stage))
    Write-Detail (Get-Label 'sign-in-url.ouvrir-par-icone')
    exit 3
}

Write-Step (Get-Label 'sign-in-url.etape-serveur')
if (-not $Port) { $Port = [int](Get-Config -Backend $backend).Port }
if (-not (Get-PortListener -Port $Port)) {
    Write-Fail (Get-Label 'sign-in-url.personne-n-ecoute' $Port)
    exit 2
}

$account = Get-ProcessAccount
Write-Step (Get-Label 'sign-in-url.etape-adresse' $account)
# LE DELAI EST COURT ET IL EST DIT. Le serveur repond en quelques dixiemes de seconde ou
# ne repond pas : attendre plus longtemps n'a jamais rien rendu, sinon l'impression que
# l'outil est bloque.
$target = Get-OpenUrl -Account $account -BaseUrl ('http://127.0.0.1:' + $Port) -TimeoutSec 10 -Backend $backend
if (-not $target) {
    Write-Fail (Get-Label 'sign-in-url.adresse-refusee' $account)
    exit 2
}

Write-Ok (Get-Label 'sign-in-url.adresse-prete' $account)
Write-Detail (Get-Label 'sign-in-url.valable-une-fois')
Write-Host $target
if ($Open) { Start-Process $target }
exit 0
