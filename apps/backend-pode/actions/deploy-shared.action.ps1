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
    return @{ message = "Script de déploiement introuvable : $script"; result = @{ ok = $false } }
}
$destination = if ($Params -and $Params.destination) { "$($Params.destination)" } else { 'C:\Program Files\Sowapps\Vigie' }

# Lancement en tache de fond, sortie REDIRIGEE DANS UN FICHIER.
#
# Premiere version : ProcessStartInfo avec RedirectStandardOutput sans jamais LIRE le
# flux. Le tampon du tuyau se remplit, le processus se bloque a la premiere ligne un peu
# longue -- rien ne s'est deploye et aucun journal n'a ete ecrit (constate). Start-Process
# ecrit directement dans un fichier : pas de tuyau a vider, et une trace a relire.
$journal = Join-Path (Get-LogDir -Backend $backend) ('deploy_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
$erreurs = $journal -replace '\.log$', '.err.log'
$pwsh = $null
try { $pwsh = (Get-Process -Id $PID).Path } catch { }
if (-not $pwsh) { $pwsh = 'pwsh.exe' }

$lance = $false
try {
    # Les chemins contiennent des ESPACES (« C:\Program Files\... ») : sans guillemets,
    # -Destination ne recoit que « C:\Program » et le reste devient un autre parametre.
    # Constate : le deploiement a repondu « Archive introuvable : Files\Sowapps\Vigie ».
    $argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
              '-File', ('"' + $script + '"'),
              '-Destination', ('"' + $destination + '"'),
              '-Yes')
    # Le veilleur attend la fin et rapporte le code de sortie (D82) : un deploiement
    # rate doit se voir sur la carte, pas seulement dans un journal.
    $lance = [bool](Start-WatchedAction -Module 'deployment' -Probe 'comptes.probe.ps1' `
                        -Label 'Déploiement' -Action 'deploy-shared' `
                        -File $pwsh -Arguments $argv -Log $journal -Backend $backend)
    Write-Log -Backend $backend -Name 'deploy' -Message (Get-Label 'deploy-shared.deploiement-lance-vers-journal' $destination $journal)
} catch {
    Write-Log -Backend $backend -Name 'deploy' -Level 'ERROR' -Message $_.Exception.Message
}

if (-not $lance) { return @{ message = "Impossible de lancer le déploiement."; result = @{ ok = $false } } }

@{
    message = "Déploiement lancé vers $destination. Il dure une à deux minutes ; les comptes pourront ensuite être activés."
    result  = @{ ok = $true; async = $true; module = 'deployment'; invalidate = @('comptes.probe.ps1') }
}
