# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- le serveur se relance avec SES droits, il n'en accorde aucun (D65)
# @execution: serveur   -- c'est le serveur lui-meme qui doit agir, pas un tray
<#
    Action server-restart : LE SERVEUR SE RELANCE LUI-MEME.

    POURQUOI PAS LE TRAY. Jusqu'ici, « Redemarrer le serveur » etait fait par le tray : il
    tuait le processus et en lancait un autre. Or start.ps1 exige l'elevation -- donc,
    depuis un compte standard, une fenetre UAC reclamant les identifiants d'un
    administrateur. Pour un geste aussi banal que relancer l'application.

    Le serveur, LUI, est deja eleve. Il peut donc lancer son successeur avec ses propres
    droits : personne n'a rien a autoriser. C'est la voie normale, et elle marche pour
    tous les comptes.

    Le cas ou le serveur est MORT reste different : il n'y a alors personne pour se
    relancer, et c'est au tray de demander l'elevation. Mais ce cas n'est jamais arrive.

    COMMENT. On ne peut pas se tuer et se relancer soi-meme : le processus qui meurt
    n'execute plus rien. Un RELANCEUR detache s'en charge -- il attend que le port se
    libere, puis demarre le nouveau serveur. Il attend le port et non un delai fixe :
    deux serveurs sur le meme port, c'est le second qui meurt.
#>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

<#
    UNE OPERATION EN COURS N'EST PAS COUPEE A LA LEGERE.

    Relancer pendant un deploiement laisse une installation a moitie faite, et c'est
    difficile a rattraper. On refuse donc, EN NOMMANT l'operation -- « Reessayez a la
    fin » sans dire de quoi ne sert a rien.

    « force » passe outre : c'est l'issue de secours quand l'operation est justement ce
    qui est bloque. Le choix appartient a la personne, pas a nous ; on lui donne les
    faits pour qu'elle tranche.
#>
$force = [bool]($Params -and $Params.force)
# « wait » : ne pas refuser, ATTENDRE la fin de l'operation puis relancer. C'est le
# serveur qui patiente, pas le tray : il sait ce qui tourne, et son relanceur est detache
# -- il n'a donc ni delai a inventer ni boucle a tenir de l'autre cote.
$wait  = [bool]($Params -and $Params.wait)
if (-not $force -and -not $wait) {
    $enCours = @(Get-RunningOperations -Backend $backend)
    if ($enCours.Count) {
        return @{
            message = (Get-Label 'server-restart.operation-en-cours' "$($enCours[0].label)")
            result  = @{ ok = $false; busy = $true; operation = "$($enCours[0].label)" }
        }
    }
}

$start = Join-Path $backend 'start.ps1'
if (-not (Test-Path -LiteralPath $start)) {
    return @{ message = (Get-Label 'server-restart.introuvable' $start); result = @{ ok = $false } }
}

# LE RELANCEUR EST COMMUN (Start-ServerRelauncher) : la mise a jour emprunte exactement le
# meme chemin. Deux copies du meme geste, c'est une correction sur deux qui se perd.
try {
    $null = Start-ServerRelauncher -StartScript $start -Wait:$wait -Backend $backend
} catch {
    return @{ message = (Get-Label 'server-restart.echec' $_.Exception.Message); result = @{ ok = $false } }
}

Write-Log -Backend $backend -Name 'app' -Message (Get-Label 'server-restart.journal' (Get-ActionRequester))

@{
    message = (Get-Label 'server-restart.lance')
    result  = @{ ok = $true }
}
