<#
    RESTORE-CONTEXT : REMETTRE LES REGLES EN PLACE APRES UNE COMPRESSION DE CONTEXTE.

    LE PROBLEME. Quand le contexte de l'agent est compresse, il ne reste qu'un RESUME.
    Les disciplines, les decisions et les documents de conception, eux, ne sont plus la.
    L'agent reprend alors le travail avec ses souvenirs pour seule source -- et un
    souvenir n'est pas une verification. Constate le 31/08 : j'ai annonce qu'un script
    n'etait plus appele par personne, et supprime en consequence, alors qu'un bouton de
    l'interface l'appelait toujours. La phrase venait du resume, pas du depot.

    LE PRINCIPE. On ne compte pas sur la vigilance de l'agent pour se souvenir de relire :
    ce script remet tout sous ses yeux en une commande. Le point d'entree qui y renvoie est
    doc/en/agent-working/briefing.md, valable pour n'importe quel agent ; un fichier charge
    automatiquement par l'un d'eux (CLAUDE.md pour Claude Code) n'est qu'un raccourci
    FACULTATIF vers lui, et ne porte aucune regle qui lui soit propre.

    CE QU'IL FAIT. Il n'invente rien et ne recopie rien : il RELIT les documents du depot
    et les affiche. Le jour ou une discipline change, ce script dit la nouvelle, sans
    qu'on ait a y toucher. Si un document a disparu, il le dit et sort en erreur -- un
    point de reprise qui renvoie vers un fichier absent est pire que pas de point du tout.

    Codes de retour : 0 = tout est la ; 1 = un document de reference manque.
#>
[CmdletBinding()]
param(
    # -Court : la carte des documents et l'etat du depot, sans le texte des disciplines.
    # Pour une reprise en cours de session, quand les regles sont encore fraiches.
    [switch] $Court
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')

Write-Title (Get-Label 'restore-context.titre')

<#
    LA CARTE DES DOCUMENTS. Le role de chacun est ecrit ici et NULLE PART AILLEURS sous
    cette forme : ce sont des phrases d'orientation, pas un doublon du contenu. Le
    contenu, lui, reste dans les fichiers -- qu'on affiche plus bas.

    La cle du libelle est ECRITE, pas calculee : check-labels lit les appels a froid et ne
    peut verifier que ce qu'il voit. Une cle rangee dans une variable passe le controle
    sans etre verifiee -- et c'est exactement la que le libelle manquant se cache.
#>
$documents = @(
    @{ path = 'doc/en/agent-working/briefing.md';     role = (Get-Label 'restore-context.role-briefing') }
    @{ path = 'doc/en/agent-working/disciplines.md';  role = (Get-Label 'restore-context.role-disciplines') }
    @{ path = 'doc/progress/decisions.md';            role = (Get-Label 'restore-context.role-decisions') }
    @{ path = 'doc/progress/targeting';               role = (Get-Label 'restore-context.role-targeting') }
    @{ path = 'doc/progress/implemented';             role = (Get-Label 'restore-context.role-implemented') }
)

$manquants = 0
Write-Step (Get-Label 'restore-context.etape-documents')
foreach ($d in $documents) {
    $complet = Join-Path $repoRoot $d.path
    if (Test-Path -LiteralPath $complet) {
        Write-Detail ($d.path + ' — ' + $d.role)
    } else {
        Write-Fail (Get-Label 'restore-context.document-introuvable' $d.path)
        $manquants++
    }
}

<#
    LES DISCIPLINES, EN ENTIER.

    Les resumer serait en perdre, et le resume est justement ce qui a echoue. On les
    lit telles qu'elles sont ecrites.
#>
if (-not $Court) {
    $disciplines = Join-Path $repoRoot 'doc/en/agent-working/disciplines.md'
    if (Test-Path -LiteralPath $disciplines) {
        Write-Step (Get-Label 'restore-context.etape-disciplines')
        Get-Content -LiteralPath $disciplines -Encoding UTF8 | ForEach-Object { Write-Host $_ }
    }
}

<#
    OU EN EST LE DEPOT. Le resume dit ce qui a ete fait ; git dit ce qui EST. Quand les
    deux divergent, c'est git qui a raison.
#>
Write-Step (Get-Label 'restore-context.etape-depot')
$branche = Invoke-Git -Path $repoRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
Write-Detail (Get-Label 'restore-context.branche' "$branche".Trim())
foreach ($ligne in @(Invoke-Git -Path $repoRoot -Arguments @('log', '--oneline', '-5'))) {
    if ("$ligne".Trim()) { Write-Detail "$ligne" }
}
$enCours = @(Invoke-Git -Path $repoRoot -Arguments @('status', '--short') | Where-Object { "$_".Trim() })
if ($enCours.Count) {
    Write-Warn (Get-Label 'restore-context.travail-en-cours' $enCours.Count)
    foreach ($ligne in $enCours) { Write-Detail "$ligne" }
} else {
    Write-Detail (Get-Label 'restore-context.rien-en-cours')
}

<#
    CE QU'ON NE CONCLUT PAS SANS PREUVE.

    Une seule regle est rappelee ici, parce que c'est celle que la compression fait
    enfreindre : le resume affirme des etats du depot (« plus utilise », « deja
    corrige », « eprouve »), et ces affirmations vieillissent. Les vérificateurs, eux,
    ne vieillissent pas.
#>
Write-Step (Get-Label 'restore-context.etape-preuve')
Write-Detail (Get-Label 'restore-context.preuve-reachable')
Write-Detail (Get-Label 'restore-context.preuve-decisions')
Write-Detail (Get-Label 'restore-context.preuve-verificateurs')

if ($manquants) {
    Write-Fail (Get-Label 'restore-context.documents-manquants' $manquants)
    exit 1
}
Write-Ok (Get-Label 'restore-context.pret')
exit 0
