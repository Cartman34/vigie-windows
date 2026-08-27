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
    -Help "Numéro de version ET commit : deux versions portant le même numéro peuvent différer de vingt commits." `
    -Guide ("Source de la marque : " + $marque.source + [Environment]::NewLine + "Racine : " + (Get-RepoRoot))

$cfg = Get-Config -Backend $backend
$fields += New-Field -Key 'serveur' -Label 'Serveur' `
    -Value ("$($cfg.BindAddress):$($cfg.Port)" + $(if ($eleve) { ' · élevé' } else { ' · non élevé' })) `
    -Kind 'text' -Status 'neutral' `
    -Help "Adresse d'écoute et niveau de privilège du processus qui rend cette page."

# --- Les dependances ----------------------------------------------------------
$pwshMachine = Get-SharedPwshPath
$pwshCompte  = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
$fields += New-Field -Key 'pwsh' -Label 'PowerShell 7' `
    -Value $(if ($pwshMachine) { 'Installé' } elseif ($pwshCompte) { 'Ce compte seulement' } else { 'Absent' }) `
    -Kind 'text' -Status $(if ($pwshMachine) { 'ok' } elseif ($pwshCompte) { 'warn' } else { 'error' }) `
    -FixAction $(if ($pwshMachine) { '' } else { 'pwsh-install-machine' }) `
    -Help "Les tâches de démarrage lancent cet interpréteur. Installé pour un seul compte, il vit dans son profil : les autres comptes ne peuvent pas le lancer." `
    -Guide $(if ($pwshMachine) { $pwshMachine } elseif ($pwshCompte) { $pwshCompte } else { 'Aucun interpréteur trouvé' })

$pode = @(Get-Module -ListAvailable -Name Pode | Sort-Object Version -Descending | Select-Object -First 1)
$fields += New-Field -Key 'pode' -Label 'Module Pode' `
    -Value $(if ($pode.Count) { 'v' + $pode[0].Version } else { 'Absent' }) -Kind 'text' `
    -Status $(if ($pode.Count) { 'ok' } else { 'error' }) `
    -Help "Le serveur web de Vigie, installé par setup.cmd." `
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
    -Help "Vigie démarre par une tâche planifiée, une par compte. Une tâche qui vise un interpréteur disparu se lance et meurt sans un mot." `
    -Guide ((@($taches | ForEach-Object {
                $mal = Get-VigieTaskAilment -Task $_
                "$($_.TaskName) -> " + $(if ($mal) { "HORS SERVICE : $mal" } else { "$(@($_.Actions)[0].Execute)" })
            }) -join [Environment]::NewLine))

if (-not $eleve) {
    $fields += New-Field -Key 'portee' -Label 'Portée de ce relevé' -Value 'Session non élevée' -Kind 'text' -Status 'neutral' `
        -Help "Les tâches des AUTRES comptes ne sont pas visibles d'une session ordinaire : ce relevé peut être incomplet."
}

# --- Ou vivent les donnees ----------------------------------------------------
$dossierLog = Get-VarPath -Backend $backend -Kind 'log'
$journaux = @(Get-ChildItem -Path $dossierLog -Filter '*.log' -File -ErrorAction SilentlyContinue)
$poids = 0
foreach ($j in $journaux) { $poids += $j.Length }
$fields += New-Field -Key 'journaux' -Label 'Journaux' `
    -Value ("$($journaux.Count) fichier(s) · " + (Format-ByteSize -Bytes $poids)) -Kind 'text' -Status 'neutral' `
    -FixAction 'open-logs' `
    -Help "Tout ce que Vigie fait s'écrit là : démarrages, sondes, actions, déploiements, erreurs." `
    -Guide ($dossierLog + [Environment]::NewLine +
            (@($journaux | Sort-Object LastWriteTime -Descending | Select-Object -First 8 |
               ForEach-Object { "  " + $_.Name + "  (" + (Format-ByteSize -Bytes $_.Length) + ")" }) -join [Environment]::NewLine))

# UN CHEMIN N'EST PAS UNE VALEUR DE CARTE : il tient sur trois lignes, se lit mal, et
# n'apprend rien au premier coup d'oeil. La carte dit CE QUE C'EST et son poids ; le
# chemin complet vit dans le detail de la ligne (regle utilisateur, 27/08).
$racineVar = Get-VarRoot -Backend $backend
$poidsVar = 0
try {
    $poidsVar = (Get-ChildItem -LiteralPath $racineVar -Recurse -File -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum
} catch { }
$fields += New-Field -Key 'donnees' -Label 'Données locales' `
    -Value $(if ($poidsVar) { Format-ByteSize -Bytes $poidsVar } else { 'Aucune' }) -Kind 'text' -Status 'neutral' `
    -Help "Cache, historique, jeton et journaux de CE compte. Chaque compte a les siens." `
    -Guide $racineVar

# L'INSTALLATION PARTAGEE est-elle a jour ? (version ET commit, D84)
$cmp = Compare-SharedInstall -Backend $backend
if ($cmp) {
    # La VALEUR dit la version, la COULEUR dit si elle est a jour, le DETAIL explique.
    $etatDeploiement = if ($cmp.same) { "Elle correspond exactement à ce dépôt." }
                       elseif ($null -ne $cmp.behind -and $cmp.behind -gt 0) { "Elle est en retard de $($cmp.behind) commit(s) sur ce dépôt." }
                       else { "L'écart avec ce dépôt n'est pas mesurable : elle a été déployée avant que Vigie ne marque ses archives." }
    $fields += New-Field -Key 'deploiement' -Label 'Installation partagée' `
        -Value $cmp.there.version -Kind 'text' `
        -Status $(if ($cmp.same) { 'ok' } else { 'warn' }) `
        -FixAction $(if ($cmp.same) { '' } else { 'vigie-update' }) `
        -Help "La version que lancent les AUTRES comptes. Elle ne change qu'au déploiement." `
        -Guide ($etatDeploiement + [Environment]::NewLine + $cmp.path)
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
        -Help "Réécrit les tâches planifiées de Vigie qui ne peuvent plus lancer l'application." `
        -Impact ("Réécrit UNIQUEMENT les tâches nommées « Vigie » et « Vigie - <compte> » : leur interpréteur " +
                 "devient celui installé pour la machine, et leur chemin celui de l'installation en service. " +
                 "Aucune autre tâche planifiée n'est touchée, aucune tâche n'est créée ni supprimée.") `
        -Usage "Quand Vigie ne démarre plus à l'ouverture de session, ou après un changement d'installation de PowerShell." `
        -Reversible "Sans objet : la tâche est simplement remise dans un état où elle fonctionne."
    New-Action -Id 'vigie-update' -Label 'Mettre à jour Vigie' -Kind 'confirm' -Severity 'fix' -Confirm `
        -BusyLabel 'Mise à jour…' `
        -Help "Déploie la version de ce dépôt vers l'installation partagée, puis relance l'application avec." `
        -Impact ("Deux étapes enchaînées : déploiement vers C:\Program Files\Sowapps\Vigie (tag de version posé), puis relance du tray " +
                 "ET du serveur. L'interface se coupe quelques secondes et la page se reconnecte seule. " +
                 "Réglages, historique et journaux sont conservés.") `
        -Usage "Quand l'installation partagée est en retard sur le dépôt : les autres comptes lancent alors une version plus ancienne que la vôtre." `
        -Reversible ("La relance, oui : Vigie repart de toute façon. Le déploiement se défait en redéployant une " +
                     "version antérieure. Si le déploiement échoue, la relance N'A PAS LIEU — l'ancienne version continue de tourner.")
    New-Action -Id 'open-logs' -Label 'Ouvrir les journaux' -Kind 'manual' -Severity 'info' `
        -Help "Ouvre le dossier des journaux dans l'explorateur."
)
