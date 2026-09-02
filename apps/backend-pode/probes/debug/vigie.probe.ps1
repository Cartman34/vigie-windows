# @author Florent HAZARD <f.hazard@sowapps.com>
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

<#
    LES SENTINELLES, ET CE QU'ELLES ONT RELEVE EN DERNIER.

    Leur memoire vit dans le var du compte qui EXECUTE l'app serveur : une session
    ordinaire ne peut meme pas la lire, et mon outil de suivi annoncait « jamais relevee »
    alors qu'il ne savait tout simplement pas (constate le 01/09). C'est Vigie qui doit le
    dire -- elle, elle voit.

    C'est aussi la seule preuve qu'on ait que la veille tourne : sans releve, elle est
    peut-etre arretee depuis des heures sans que rien ne le signale.
#>
$sentinels = @()
try { $sentinels = @(Get-WatchDeclarations -Backend $backend) } catch { }
if ($sentinels.Count) {
    $memory = @{}
    try {
        $memoryPath = Get-WatchMemoryPath -Backend $backend
        if (Test-PathSafe $memoryPath) {
            $j = Get-Content -LiteralPath $memoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($pr in $j.PSObject.Properties) { $memory[$pr.Name] = $pr.Value }
        }
    } catch { }

    $never = @($sentinels | Where-Object { -not $memory[$_.Key] })
    $lines = @()
    $oldest = $null
    foreach ($s in $sentinels) {
        $seen = $memory[$s.Key]
        if ($seen) {
            $when = $null
            try { $when = (ConvertTo-UtcDate $seen.at).ToLocalTime() } catch { }
            if ($when -and (-not $oldest -or $when -lt $oldest)) { $oldest = $when }
            $lines += ("{0} : « {1} » à {2}" -f $s.Key, "$($seen.value)",
                        $(if ($when) { $when.ToString('HH:mm:ss') } else { '?' }))
        } else {
            $lines += ("{0} : jamais relevée" -f $s.Key)
        }
    }

    # ELLE TOURNE, OU ELLE NE TOURNE PLUS. Un releve plus vieux que trois fois sa cadence
    # la plus lente n'est pas un retard, c'est un arret.
    $staleAfter = ([int](($sentinels | Measure-Object Seconds -Maximum).Maximum)) * 3
    $stopped = $never.Count -eq $sentinels.Count
    if (-not $stopped -and $oldest) { $stopped = ((Get-Date) - $oldest).TotalSeconds -gt $staleAfter }

    $fields += New-Field -Key 'veille' -Label 'Veille' `
        -Value $(if ($stopped) { 'À l''arrêt' } else { "$($sentinels.Count) sentinelle(s)" }) `
        -Kind 'text' -Status $(if ($stopped) { 'warn' } else { 'ok' }) `
        -FixAction $(if ($stopped) { 'server-restart' } else { $null }) `
        -Help "Les relevés que l'app serveur exécute en permanence, même sans session ouverte. Quand l'un d'eux change de valeur, les cartes concernées sont recalculées." `
        -Guide ($lines -join [Environment]::NewLine)
}

# LES RESIDENTS : CE QUI VIT A COTE DE L'APP SERVEUR (targeting/residents.md).
# Une surveillance dont on ne sait pas si elle fonctionne ne vaut rien -- c'est le contrat
# d'un resident d'etre observable, et c'est ici qu'on le voit.
$residents = @(Get-ResidentHealth -Backend $backend)
if ($residents.Count) {
    $down = @($residents | Where-Object { -not $_.Operational })
    $residentLines = @($residents | ForEach-Object {
        $health = if ($_.Operational) { 'opérationnel' } elseif ($_.Alive) { 'vivant mais INOPÉRANT' } else { 'MORT' }
        $ligne = "- {0} : {1} ({2})" -f $_.Label, $health, $_.State
        if ($_.LastEvent) { $ligne += " — dernier événement : $($_.LastEvent)" }
        if ($_.Error)     { $ligne += " — $($_.Error)" }
        $ligne
    })
    $fields += New-Field -Key 'residents' -Label 'Résidents' `
        -Value $(if ($down.Count) { "$($down.Count) à l'arrêt sur $($residents.Count)" } else { "$($residents.Count) en vie" }) `
        -Kind 'text' -Status $(if ($down.Count) { 'warn' } else { 'ok' }) `
        -FixAction $(if ($down.Count) { 'server-restart' } else { $null }) `
        -Help "Ce qui vit en permanence à côté de l'app serveur : elle les arme à son démarrage et les réarme s'ils meurent." `
        -Guide ($residentLines -join [Environment]::NewLine)
}

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
