# @droits: admin   -- installe hors du profil et pose des taches : Windows exige l'elevation (D65)
# @libelle: Deployer pour tous les comptes | confirm | fix   -- affiche quand un champ cite cette action (D66)
<# Action : deploie cette version a un emplacement lisible par TOUS les comptes.

   Pourquoi depuis l'interface : sur un poste de developpement (ou un depot clone), Vigie
   vit dans l'espace personnel de quelqu'un et les autres comptes ne peuvent pas la lire.
   L'ecran des comptes le dit -- autant proposer le geste au meme endroit, plutot que
   d'envoyer l'utilisateur en ligne de commande.

   Le travail lui-meme est fait par scripts/deploy-prod.ps1 (fabrication de l'archive
   depuis git, copie, conservation des reglages de la machine) : une seule mise en oeuvre,
   ici comme en ligne de commande. Tache de fond : la fabrication de l'archive prend du
   temps. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$script = Join-Path (Get-RepoRoot) 'scripts/deploy-prod.ps1'
if (-not (Test-Path -LiteralPath $script)) {
    return @{ message = "Script de deploiement introuvable : $script"; result = @{ ok = $false } }
}
$destination = if ($Params -and $Params.destination) { "$($Params.destination)" } else { 'C:\Program Files\Sowapps\Vigie' }

# Start-DetachedAction impose sa propre signature (-Backend/-ArgsB64) : ce script-ci
# attend -Destination/-Yes. On le lance donc directement, fenetre cachee. Le serveur est
# deja eleve : aucune invite supplementaire.
$journal = Join-Path (Get-LogDir -Backend $backend) ('deploy_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
$pwsh = (Get-Process -Id $PID).Path
if (-not $pwsh) { $pwsh = 'pwsh.exe' }
$lance = $false
try {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $pwsh
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $script +
                     '" -Destination "' + $destination + '" -Yes'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = (Get-RepoRoot)
    $proc = [System.Diagnostics.Process]::Start($psi)
    # La sortie part au journal : un deploiement qui echoue doit laisser une trace.
    $null = Register-ObjectEvent -InputObject $proc -EventName Exited -Action {
        try { $Event.MessageData | Out-Null } catch { }
    } -MessageData $journal -ErrorAction SilentlyContinue
    $lance = [bool]$proc
    Write-Log -Backend $backend -Name 'deploy' -Message ("deploiement lance vers " + $destination)
} catch { Write-Log -Backend $backend -Name 'deploy' -Level 'ERROR' -Message $_.Exception.Message }
if (-not $lance) { return @{ message = "Impossible de lancer le deploiement."; result = @{ ok = $false } } }

@{
    message = "Deploiement lance vers $destination. Il dure une a deux minutes ; les comptes pourront ensuite etre actives."
    result  = @{ ok = $true; async = $true; module = 'accounts'; invalidate = @('comptes.probe.ps1') }
}
