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
    return @{ message = "Aucune mise a jour selectionnee."; result = @{ ok = $false } }
}

# Le verrou du Mode MAJ bloque l'installation : le dire AVANT plutot que de laisser
# echouer une operation de plusieurs minutes.
try {
    if (Test-UpdateTasksAclLock) {
        return @{
            message = "Les mises a jour sont verrouillees (Mode MAJ). Deverrouillez avant d'installer."
            result  = @{ ok = $false; verrou = $true }
        }
    }
} catch { }

$outFile = Get-VarPath -Backend $backend -Kind 'cache' -File 'wu-install.json'
Update-StateJson -Path $outFile -Set @{
    installing = $true; phase = 'demarrage'; total = $ids.Count
    at = (Get-Date).ToUniversalTime().ToString('o')
} | Out-Null

$worker = Join-Path $backend 'workers/wu-install.worker.ps1'
try {
    $null = Start-DetachedAction -Script $worker -ArgsMap @{ ids = $ids } -Backend $backend
} catch {
    Update-StateJson -Path $outFile -Set @{ installing = $false; error = $_.Exception.Message } | Out-Null
    return @{ message = "Impossible de lancer l'installation : $($_.Exception.Message)"; result = @{ ok = $false } }
}

@{
    message = "Installation de $($ids.Count) mise(s) a jour lancee en tache de fond."
    result  = @{ ok = $true; async = $true; module = 'wu-pending'; invalidate = @('pending.probe.ps1') }
}
