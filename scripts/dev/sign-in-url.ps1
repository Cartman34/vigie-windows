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

    Codes de retour : 0 = adresse rendue ; 2 = serveur muet, ou secret illisible.
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

if (-not $Port) { $Port = [int](Get-Config -Backend $backend).Port }
if (-not (Get-PortListener -Port $Port)) {
    Write-Fail (Get-Label 'sign-in-url.personne-n-ecoute' $Port)
    exit 2
}

$account = Get-ProcessAccount
$target = Get-OpenUrl -Account $account -BaseUrl ('http://127.0.0.1:' + $Port) -Backend $backend
if (-not $target) {
    Write-Fail (Get-Label 'sign-in-url.adresse-refusee' $account)
    exit 2
}

Write-Ok (Get-Label 'sign-in-url.adresse-prete' $account)
Write-Detail (Get-Label 'sign-in-url.valable-une-fois')
Write-Host $target
if ($Open) { Start-Process $target }
exit 0
