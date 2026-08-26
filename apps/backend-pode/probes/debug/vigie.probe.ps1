<# Sonde : l'etat de VIGIE ELLE-MEME. LECTURE SEULE.

   Pourquoi cette carte existe (D85) : tout ce qui a fait perdre du temps le 26/08 etait
   invisible depuis l'application. Une tache de demarrage visant un interpreteur disparu,
   une dependance installee pour un seul compte, une installation partagee en retard de
   vingt commits : rien de tout cela n'apparaissait nulle part, et il a fallu fouiller le
   registre et les journaux a la main.

   Elle est ETEINTE par defaut : c'est un outil de depannage, pas une carte de tous les
   jours. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$fields = @()
$eleve  = Test-IsElevated

# --- Ce qui tourne ------------------------------------------------------------
$marque = Get-BuildStamp
$court  = if ($marque.commit) { $marque.commit.Substring(0, [Math]::Min(8, $marque.commit.Length)) } else { '' }
$fields += New-Field -Key 'version' -Label 'Version en cours' `
    -Value ($marque.version + $(if ($court) { ' · ' + $court } else { '' })) `
    -Kind 'text' -Status 'neutral' `
    -Help "Numero de version ET commit : deux versions portant le meme numero peuvent differer de vingt commits." `
    -Guide ("Source de la marque : " + $marque.source + [Environment]::NewLine + "Racine : " + (Get-RepoRoot))

$cfg = Get-Config -Backend $backend
$fields += New-Field -Key 'serveur' -Label 'Serveur' `
    -Value ("$($cfg.BindAddress):$($cfg.Port)" + $(if ($eleve) { ' · élevé' } else { ' · non élevé' })) `
    -Kind 'text' -Status 'neutral' `
    -Help "Adresse d'ecoute et niveau de privilege du processus qui rend cette page."

# --- Les dependances ----------------------------------------------------------
$pwshMachine = Get-SharedPwshPath
$pwshCompte  = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
$fields += New-Field -Key 'pwsh' -Label 'PowerShell 7' `
    -Value $(if ($pwshMachine) { 'installé pour la machine' } elseif ($pwshCompte) { 'ce compte seulement' } else { 'absent' }) `
    -Kind 'text' -Status $(if ($pwshMachine) { 'ok' } elseif ($pwshCompte) { 'warn' } else { 'error' }) `
    -FixAction $(if ($pwshMachine) { '' } else { 'pwsh-install-machine' }) `
    -Help "Les taches de demarrage lancent cet interpreteur. Installe pour un seul compte, il vit dans son profil : les autres comptes ne peuvent pas le lancer." `
    -Guide $(if ($pwshMachine) { $pwshMachine } elseif ($pwshCompte) { $pwshCompte } else { 'aucun interpreteur trouve' })

$pode = @(Get-Module -ListAvailable -Name Pode | Sort-Object Version -Descending | Select-Object -First 1)
$fields += New-Field -Key 'pode' -Label 'Module Pode' `
    -Value $(if ($pode.Count) { 'v' + $pode[0].Version } else { 'absent' }) -Kind 'text' `
    -Status $(if ($pode.Count) { 'ok' } else { 'error' }) `
    -Help "Le serveur web de Vigie, installe par setup.cmd." `
    -Guide $(if ($pode.Count) { "$($pode[0].Path)" } else { 'Relancez setup.cmd.' })

# --- Le demarrage automatique -------------------------------------------------
# On ne repare RIEN ici (une sonde lit) : on constate, et on cite le bouton qui repare.
$taches = @()
try {
    $taches = @(Get-ScheduledTask -ErrorAction Stop |
                Where-Object { "$($_.TaskName)" -eq 'Vigie' -or "$($_.TaskName)".StartsWith('Vigie - ') })
} catch { }
$malades = @($taches | Where-Object { Get-VigieTaskAilment -Task $_ })
$fields += New-Field -Key 'taches' -Label 'Tâches de démarrage' `
    -Value ("$($taches.Count) tâche(s)" + $(if ($malades.Count) { ", dont $($malades.Count) hors service" } else { ", toutes saines" })) `
    -Kind 'text' -Status $(if ($malades.Count) { 'error' } elseif ($taches.Count) { 'ok' } else { 'warn' }) `
    -FixAction $(if ($malades.Count -or -not $taches.Count) { 'repair-tasks' } else { '' }) `
    -Help "Vigie demarre par une tache planifiee, une par compte. Une tache qui vise un interpreteur disparu se lance et meurt sans un mot." `
    -Guide ((@($taches | ForEach-Object {
                $mal = Get-VigieTaskAilment -Task $_
                "$($_.TaskName) -> " + $(if ($mal) { "HORS SERVICE : $mal" } else { "$(@($_.Actions)[0].Execute)" })
            }) -join [Environment]::NewLine))

if (-not $eleve) {
    $fields += New-Field -Key 'portee' -Label 'Portée de ce relevé' -Value 'session non élevée' -Kind 'text' -Status 'neutral' `
        -Help "Les taches des AUTRES comptes ne sont pas visibles d'une session ordinaire : ce releve peut etre incomplet."
}

# --- Ou vivent les donnees ----------------------------------------------------
$dossierLog = Get-VarPath -Backend $backend -Kind 'log'
$journaux = @(Get-ChildItem -Path $dossierLog -Filter '*.log' -File -ErrorAction SilentlyContinue)
$poids = 0
foreach ($j in $journaux) { $poids += $j.Length }
$fields += New-Field -Key 'journaux' -Label 'Journaux' `
    -Value ("$($journaux.Count) fichier(s) · " + (Format-ByteSize -Bytes $poids)) -Kind 'text' -Status 'neutral' `
    -FixAction 'open-logs' `
    -Help "Tout ce que Vigie fait s'ecrit la : demarrages, sondes, actions, deploiements, erreurs." `
    -Guide ($dossierLog + [Environment]::NewLine +
            (@($journaux | Sort-Object LastWriteTime -Descending | Select-Object -First 8 |
               ForEach-Object { "  " + $_.Name + "  (" + (Format-ByteSize -Bytes $_.Length) + ")" }) -join [Environment]::NewLine))

$fields += New-Field -Key 'donnees' -Label 'Données locales' -Value (Get-VarRoot -Backend $backend) -Kind 'text' -Status 'neutral' `
    -Help "Cache, historique, jeton et journaux de CE compte. Chaque compte a les siens."

# L'INSTALLATION PARTAGEE est-elle a jour ? (version ET commit, D84)
$cmp = Compare-SharedInstall -Backend $backend
if ($cmp) {
    $etatDeploiement = if ($cmp.same) { 'a jour' }
                       elseif ($null -ne $cmp.behind -and $cmp.behind -gt 0) { 'en retard de ' + $cmp.behind + ' commit(s)' }
                       else { 'ecart inconnu' }
    $fields += New-Field -Key 'deploiement' -Label 'Installation partagée' `
        -Value ($cmp.there.version + ' · ' + $etatDeploiement) -Kind 'text' `
        -Status $(if ($cmp.same) { 'ok' } else { 'warn' }) `
        -FixAction $(if ($cmp.same) { '' } else { 'vigie-update' }) `
        -Help "La version que lancent les AUTRES comptes. Elle ne change qu'au deploiement." `
        -Guide ($cmp.path)
}

# LE SORT DE LA DERNIERE OPERATION lancee depuis cette carte (D82).
$dernier = New-LastRunField -Module 'vigie-debug' -Backend $backend
if ($dernier) { $fields += $dernier }

$pire = if (@($fields | Where-Object { "$($_.status)" -eq 'error' }).Count) { 'error' }
        elseif (@($fields | Where-Object { "$($_.status)" -eq 'warn' }).Count) { 'warn' }
        else { 'ok' }

New-ModuleObject -Id 'vigie-debug' -Theme 'debug' -Label 'Vigie' -Status $pire -Fields $fields -Actions @(
    New-Action -Id 'repair-tasks' -Label 'Réparer le démarrage de Vigie' -Kind 'immediate' -Severity 'fix' `
        -BusyLabel 'Réparation…' `
        -Help "Reecrit les taches de demarrage de Vigie qui ne fonctionnent plus. Ne touche a rien d'autre sur la machine."
    New-Action -Id 'vigie-update' -Label 'Mettre à jour Vigie' -Kind 'confirm' -Severity 'fix' -Confirm `
        -BusyLabel 'Mise à jour…' `
        -Help "Redeploie l'installation partagee depuis ce depot, puis relance Vigie. Les reglages sont conserves."
    New-Action -Id 'open-logs' -Label 'Ouvrir les journaux' -Kind 'manual' -Severity 'info' `
        -Help "Ouvre le dossier des journaux dans l'explorateur."
)
