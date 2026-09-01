# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- modifie le systeme : Windows exige l'elevation (D65)
<# Action : installe les mises a jour Windows CHOISIES par l'utilisateur.

   Recoit params.ids = identifiants renvoyes par wu-list-pending. Rien n'est installe sans
   choix explicite : une liste vide est refusee plutot qu'interpretee comme « tout ».

   L'installation part dans un worker DETACHE (elle dure des minutes) : la requete HTTP
   rend la main tout de suite, la carte passe « en cours » et se met a jour seule. Fermer
   le navigateur n'interrompt donc rien.
#>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$ids = @()
if ($Params -and $Params.ids) { $ids = @($Params.ids | Where-Object { "$_" -match '\S' } | ForEach-Object { "$_" }) }
if ($ids.Count -eq 0) {
    return @{ message = "Aucune mise à jour sélectionnée."; result = @{ ok = $false } }
}

# Le verrou du Mode MAJ est une mecanique INTERNE a l'application : elle le leve le temps
# d'installer, puis le REPOSE. L'utilisateur est prevenu, pas bloque -- lui demander de
# defaire a la main un verrou que l'application a pose elle-meme n'a pas de sens.
$etaitVerrouille = $false
try { $etaitVerrouille = Test-UpdateTasksAclLock } catch { }

$outFile = Get-VarPath -Backend $backend -Kind 'cache' -File 'wu-install.json'
Update-StateJson -Path $outFile -Set @{
    installing = $true; phase = 'demarrage'; total = $ids.Count
    at = (Get-Date).ToUniversalTime().ToString('o')
} | Out-Null

$worker = Join-Path $backend 'workers/wu-install.worker.ps1'
try {
    $null = Start-DetachedAction -Script $worker -ArgsMap @{ ids = $ids; reposerVerrou = $etaitVerrouille } -Backend $backend
} catch {
    Update-StateJson -Path $outFile -Set @{ installing = $false; error = $_.Exception.Message } | Out-Null
    return @{ message = "Impossible de lancer l'installation : $($_.Exception.Message)"; result = @{ ok = $false } }
}

$avis = if ($etaitVerrouille) { " Le verrou du Mode MAJ est levé le temps de l'opération, puis reposé." } else { "" }
@{
    message = "Installation de $($ids.Count) mise(s) à jour lancée en tâche de fond.$avis"
    result  = @{ ok = $true; async = $true; module = 'wu-pending'; invalidate = @('pending.probe.ps1','lock.probe.ps1') }
}
