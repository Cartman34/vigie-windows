# @droits: admin   -- redeploie hors du profil et relance l'application (D65)
# @libelle: Mettre a jour Vigie | confirm | fix   -- affiche quand un champ cite cette action (D66)
<# Action : met a jour Vigie, puis la relance.

   D'ou vient le code depend de la machine, et vigie-update.ps1 tranche tout seul (D99) :
   un poste de DEVELOPPEMENT deploie son depot local (et pose le tag au passage), une
   machine INSTALLEE telecharge la derniere version publiee sur GitHub.

   Ce que ca fait, dans l'ordre :
     1. rapporte une archive et la VERIFIE (vigie-fetch.ps1) -- tant qu'elle n'est pas
        exploitable, l'installation en place n'est pas touchee ;
     2. la deploie (deploy-prod.ps1), en conservant les reglages de la machine ;
     3. depose l'ordre « restart » au tray, qui relance le serveur avec le nouveau code.

   Le tout sous le VEILLEUR (D82) : le code de sortie est constate et rapporte, une
   mise a jour ratee devient une ligne rouge sur la carte au lieu d'un silence. Le code
   3 -- deja a jour -- n'est PAS un echec (D77). #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$script = Join-Path (Get-RepoRoot) 'scripts/vigie-update.ps1'
if (-not (Test-Path -LiteralPath $script)) {
    return @{ message = "Script de mise à jour introuvable : $script"; result = @{ ok = $false } }
}

$journal = Join-Path (Get-LogDir -Backend $backend) ('update_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
$pwsh = $null
try { $pwsh = (Get-Process -Id $PID).Path } catch { }
if (-not $pwsh) { $pwsh = 'pwsh.exe' }

$lance = $false
try {
    # Guillemets : les chemins contiennent des espaces (« C:\Program Files\... »).
    $argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
              '-File', ('"' + $script + '"'))
    # La carte DEPLOIEMENT gere les deploiements -- et elle est toujours la. La carte de
    # debogage, elle, peut etre eteinte : le suivi de l'operation y aurait ete invisible.
    $lance = [bool](Start-WatchedAction -Module 'deployment' -Probe 'comptes.probe.ps1' `
                        -Label 'Mise à jour de Vigie' -Action 'vigie-update' `
                        -File $pwsh -Arguments $argv -Log $journal -Backend $backend)
    Write-Log -Backend $backend -Name 'update' -Message (Get-Label 'vigie-update.mise-jour-lancee-journal' $journal)
} catch {
    Write-Log -Backend $backend -Name 'update' -Level 'ERROR' -Message $_.Exception.Message
}

if (-not $lance) { return @{ message = "Impossible de lancer la mise à jour."; result = @{ ok = $false } } }

@{
    message = "Mise à jour lancée. Elle dure une trentaine de secondes, puis Vigie redémarre toute seule."
    result  = @{ ok = $true; async = $true; module = 'deployment'; invalidate = @('comptes.probe.ps1') }
}
