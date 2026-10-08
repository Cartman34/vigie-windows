# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- le serveur se relance avec SES droits, il n'en accorde aucun (D65)
# @execution: serveur   -- c'est le serveur lui-meme qui doit agir, pas une app cliente
# @libelle: Redémarrer le serveur | confirm | fix   -- the words of the client app menu, for the same gesture (D66)
<#
    The server-restart action: THE SERVER RESTARTS ITSELF.

    Intent: make restarting the application a banal gesture for every account. WHY NOT THE CLIENT APP. Until now,
    restarting the server was done by the client app: it killed the process and started another. But start.ps1
    demands elevation -- so, from a standard account, a UAC window asking for an administrator's credentials. For
    a gesture as ordinary as restarting the application.

    The server, for ITS part, is already elevated. So it can start its successor with its own rights: nobody has
    anything to authorise. That is the normal road, and it works for every account.

    The case where the server is DEAD stays different: there is then nobody to restart itself, and it is up to
    the client app to ask for the elevation. But that case has never happened.

    HOW. One cannot kill and restart oneself: the process that dies runs nothing any more. A detached RELAUNCHER
    takes care of it -- it waits for the port to be released, then starts the new server. It waits for the port
    and not for a fixed delay: with two servers on the same port, the second one dies.
#>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

<#
    AN OPERATION UNDER WAY IS NOT CUT OFF LIGHTLY.

    Restarting during a deployment leaves an installation half done, and that is hard to recover from. So we
    refuse, NAMING the operation -- "try again at the end" without saying of what is of no use.

    "force" overrides it: that is the emergency way out when the operation is precisely what is stuck. The choice
    belongs to the person, not to us; we give them the facts so they can decide.
#>
$force = [bool]($Params -and $Params.force)
# "wait": do not refuse, WAIT for the operation to end then restart. It is the server that waits, not the client
# app: it knows what is running, and its relauncher is detached -- so it has neither a delay to invent nor a loop
# to hold on the other side.
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

# THE RELAUNCHER IS SHARED (Start-ServerRelauncher): the update takes exactly the same road. Two copies of the
# same gesture means one fix out of two gets lost.
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
