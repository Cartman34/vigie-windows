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

# --- Ce dont CE processus depend ---------------------------------------------
# PowerShell 7, les taches de demarrage et l'installation partagee ne sont PAS ici :
# elles vivent sur la carte « Deploiement ». Les avoir aux deux endroits, sous deux
# noms differents, embrouille au lieu d'informer (signale le 27/08).
$pode = @(Get-Module -ListAvailable -Name Pode | Sort-Object Version -Descending | Select-Object -First 1)
$fields += New-Field -Key 'pode' -Label 'Module Pode' `
    -Value $(if ($pode.Count) { 'v' + $pode[0].Version } else { 'Absent' }) -Kind 'text' `
    -Status $(if ($pode.Count) { 'ok' } else { 'error' }) `
    -Help "Le serveur web de Vigie, installé par setup.cmd." `
    -Guide $(if ($pode.Count) { "$($pode[0].Path)" } else { 'Relancez setup.cmd.' })

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

# LE SORT DE LA DERNIERE OPERATION lancee depuis cette carte (D82).
$dernier = New-LastRunField -Module 'vigie-debug' -Backend $backend
if ($dernier) { $fields += $dernier }

$pire = if (@($fields | Where-Object { "$($_.status)" -eq 'error' }).Count) { 'error' }
        elseif (@($fields | Where-Object { "$($_.status)" -eq 'warn' }).Count) { 'warn' }
        else { 'ok' }

New-ModuleObject -Id 'vigie-debug' -Theme 'debug' -Label 'Vigie' -Status $pire -Fields $fields -Actions @(
    New-Action -Id 'open-logs' -Label 'Ouvrir les journaux' -Kind 'manual' -Severity 'info' `
        -Help "Ouvre le dossier des journaux dans l'explorateur."
)
