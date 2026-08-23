<#
.SYNOPSIS
    Decide sans intervention humaine si une commande shell de l'agent peut s'executer.

.DESCRIPTION
    Branche sur l'evenement PreToolUse de Claude Code (voir .claude/settings.json).

    POURQUOI CE SCRIPT PLUTOT QU'UNE LISTE D'AUTORISATIONS :
    une liste « Bash(git *) » ne couvre que les commandes analysables statiquement.
    Des qu'une commande contient une boucle, une substitution $(...) ou un test [ ],
    l'analyse echoue et la permission est redemandee -- exactement la nuisance qu'on
    veut supprimer. Ce hook decide sur le TEXTE de la commande : il autorise par
    defaut et ne redemande que sur une courte liste de gestes destructeurs.

    Le garde-fou vit donc dans le depot : relisible, diffable, modifiable en un
    endroit unique, sans dependre d'une liste d'autorisations qui derive.

.INPUTS
    JSON sur l'entree standard : { "tool_name": "...", "tool_input": { "command": "..." } }

.OUTPUTS
    JSON sur la sortie standard : hookSpecificOutput.permissionDecision = allow | ask

.NOTES
    Aucune sortie / une sortie invalide = comportement par defaut de Claude Code
    (la permission est demandee). Le defaut est donc sur : en cas de panne du
    script, on retombe sur les demandes, jamais sur une autorisation muette.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Gestes qui detruisent du travail ou touchent la machine : ils restent soumis a
# validation. Motifs volontairement peu nombreux -- une liste longue finit par
# n'etre plus relue, donc plus maintenue.
$aValider = @(
    @{ Motif = '(?i)\brm\s+(-[a-z]*\s+)*-[a-z]*[rf]';           Raison = 'suppression recursive/forcee' }
    @{ Motif = '(?i)\bRemove-Item\b.*-Recurse';                  Raison = 'suppression recursive' }
    @{ Motif = '(?i)\bgit\s+push\b.*(--force|-f\b)';             Raison = 'push force (reecrit l historique distant)' }
    @{ Motif = '(?i)\bgit\s+(filter-branch|reflog\s+expire)\b';  Raison = 'reecriture d historique' }
    @{ Motif = '(?i)\bgit\s+reset\s+--hard\b';                   Raison = 'perte des modifications non validees' }
    @{ Motif = '(?i)\bgit\s+clean\b.*-[a-z]*[fx]';               Raison = 'suppression de fichiers non suivis' }
    @{ Motif = '(?i)\b(shutdown|Stop-Computer|Restart-Computer)\b'; Raison = 'arret/redemarrage de la machine' }
    @{ Motif = '(?i)\b(format|diskpart|bcdedit)\b';              Raison = 'operation disque/demarrage' }
    @{ Motif = '(?i)\b(reg|Remove-ItemProperty)\b.*\b(delete|HKLM)\b'; Raison = 'modification du registre systeme' }
    @{ Motif = '(?i)\bSet-ExecutionPolicy\b';                    Raison = 'modification d une politique de securite' }
    @{ Motif = '(?i)\b(net\s+user|takeown|icacls)\b';            Raison = 'modification de comptes ou de droits' }
    @{ Motif = '(?i)(Invoke-WebRequest|curl|wget|iwr).*\|\s*(iex|Invoke-Expression|sh|bash|pwsh)'; Raison = 'execution de code telecharge' }
)

function Write-Decision {
    param([ValidateSet('allow', 'ask')][string] $Decision, [string] $Raison)
    $sortie = @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = $Decision
            permissionDecisionReason = $Raison
        }
    }
    $sortie | ConvertTo-Json -Depth 5 -Compress
}

try {
    $brut = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($brut)) { exit 0 }   # rien a decider : defaut de l'outil
    $entree = $brut | ConvertFrom-Json
} catch {
    exit 0   # entree illisible : on laisse Claude Code demander
}

$commande = $entree.tool_input.command
if ([string]::IsNullOrWhiteSpace($commande)) { exit 0 }

foreach ($regle in $aValider) {
    if ($commande -match $regle.Motif) {
        Write-Decision -Decision 'ask' -Raison ("Validation requise : {0}." -f $regle.Raison)
        exit 0
    }
}

Write-Decision -Decision 'allow' -Raison 'Commande de travail courante (voir scripts/decider-permission.ps1).'
exit 0
