# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- lit dans le profil d'un autre compte : Windows exige l'elevation (D65)
<# An action: it fetches ANOTHER account's Vigie LOGS, for a diagnosis.

   Intent: look into another account's logs without opening a second road to them, and without ever copying a
   secret. Why an action and not an elevation on demand (the owner's choice): the Vigie server ALREADY runs
   elevated when an administrator uses it. Going through it avoids one more UAC prompt, and above all the filter
   is the same as for any sensitive action -- a standard account is refused, exactly as for the Windows Update
   lock.
   Usage: params.account = the account to diagnose. READ ONLY on the account aimed at. The API token
   (var/secrets) is NEVER copied: a secret is not copied "to have a look", and the logs are enough for a
   diagnosis. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$account = if ($Params -and $Params.account) { "$($Params.account)" } else { $null }
if (-not $account) { return @{ message = "Aucun compte precise."; result = @{ ok = $false } } }

# The account must exist on THIS machine: we are not going to read some arbitrary path.
$connu = Get-AccountByName -Name $account
if (-not $connu) { return @{ message = "Compte inconnu sur cette machine : $account"; result = @{ ok = $false } } }

$profil = Join-Path (Join-Path $env:SystemDrive 'Users') $account
# THE PATH IS BUILT BY Join-Path, never written out in full: this line carried a profile-relative path and the
# backslash before "var" was eaten on writing -- what was left was a control character, and so a folder that
# exists nowhere. The diagnosis answered that the account had never opened a session, whatever happened.
#
# The publisher is also in the path since D72. We try both, the old location possibly surviving.
$local = Join-Path (Join-Path $profil 'AppData') 'Local'
$source = $null
foreach ($candidat in @((Join-Path (Join-Path (Join-Path $local 'Sowapps') 'Vigie') 'var'),
                        (Join-Path (Join-Path $local 'Vigie') 'var'))) {
    if (Test-Path -LiteralPath $candidat) { $source = $candidat; break }
}
if (-not $source) { $source = Join-Path (Join-Path (Join-Path $local 'Sowapps') 'Vigie') 'var' }
if (-not (Test-Path -LiteralPath $source)) {
    return @{ message = "Le compte $account n'a pas encore de données Vigie : il n'a jamais ouvert de session avec Vigie active."
              result = @{ ok = $false } }
}

<#
    WE FETCH TO WHOEVER ASKS, NOT TO OURSELVES.

    The copy used to land in the SERVER APP's var -- that is, inside the service account's profile, where an
    ordinary session does not even have the right to READ. "Logs fetched: 62 files" was therefore true and
    useless: nobody but the service could open them. Observed on 31/08, while looking for why an update had
    failed.

    So they go to the requester, into THEIR Vigie data folder, which they can open with a double click. With no
    requester identified -- a call outside any session -- we fall back on the server's var: that is better than
    copying nothing.
#>
$diagRoot = $null
$asker = Get-RequesterAccount
if ($asker) {
    $askerVar = Get-AccountVarRoot -Account $asker
    if ($askerVar) { $diagRoot = Join-Path $askerVar 'log' }
}
if (-not $diagRoot) { $diagRoot = Get-VarPath -Backend $backend -Kind 'log' }
$target = Join-Path (Join-Path $diagRoot 'diag') ($account + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $target -Force | Out-Null

$nb = 0
$logs = Join-Path $source 'log'
if (Test-Path -LiteralPath $logs) {
    foreach ($f in @(Get-ChildItem -LiteralPath $logs -File -ErrorAction SilentlyContinue)) {
        Copy-Item -LiteralPath $f.FullName -Destination $target -Force
        $nb++
    }
}

<#
    AND THE STATE VIGIE WROTE ITSELF, not only its logs.

    A log says what happened; the state says what IS. On 06/10 a card was missing from the panel and the log proved
    the computation had run -- what it could not say was what the computation had READ. The answer sat in
    `cache/pkg-inventory.json`, in the service account's profile, which an ordinary session cannot even open: half an
    hour went into guessing at a file that was one copy away. The door existed and brought back the wrong half.

    So the bookkeeping comes too: `cache/` and `run/`, the JSON files Vigie writes to remember -- probe renderings,
    per-account readings, what is due, what is running. `secrets/` is still never copied, and a file over sixteen
    megabytes is named rather than copied, because a diagnosis is read in a minute and must not fill a disk.
#>
$heavy = @()
foreach ($sous in @('cache', 'run')) {
    $folder = Join-Path $source $sous
    if (-not (Test-Path -LiteralPath $folder)) { continue }
    $into = Join-Path $target $sous
    New-Item -ItemType Directory -Path $into -Force | Out-Null
    foreach ($f in @(Get-ChildItem -LiteralPath $folder -File -Recurse -ErrorAction SilentlyContinue)) {
        if ($f.Length -gt 16MB) { $heavy += ("{0}/{1} ({2})" -f $sous, $f.Name, (Format-ByteSize ([long]$f.Length))); continue }
        Copy-Item -LiteralPath $f.FullName -Destination $into -Force -ErrorAction SilentlyContinue
        $nb++
    }
}

# A summary of the state: what exists, what weight, how fresh. That is what answers "is their Vigie running, and
# since when?" without revealing anything of the content.
$summary = @("Compte    : $account", "Profil    : $profil", "Donnees   : $source",
            "Releve le : $(Get-Date -Format 's')", "")
foreach ($sous in @('cache','log','history','secrets')) {
    $d = Join-Path $source $sous
    if (-not (Test-Path -LiteralPath $d)) { $summary += ("{0,-9} : absent" -f $sous); continue }
    $f = @(Get-ChildItem -LiteralPath $d -File -Recurse -ErrorAction SilentlyContinue)
    $size = ($f | Measure-Object Length -Sum).Sum
    $recent = ($f | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    $summary += ("{0,-9} : {1} fichier(s), {2}, dernier ecrit {3}" -f $sous, $f.Count,
                (Format-ByteSize ([long]$size)), $(if ($recent) { $recent.ToString('s') } else { '-' }))
}
$summary += ""
$summary += "Le jeton d'API n'est pas copie (secrets/), volontairement."
$summary += "cache/ et run/ sont copies : c'est l'etat que Vigie ecrit pour se souvenir, et c'est lui qui dit ce qu'une carte a LU."
if ($heavy.Count) { $summary += ("Trop gros, non copie(s) : " + ($heavy -join ', ')) }
$summary -join [Environment]::NewLine | Set-Content -LiteralPath (Join-Path $target 'resume.txt') -Encoding UTF8

<#
    AND THE OLD COPIES GO. A diagnosis is read within the minute and never opened again, yet each one weighed 163 MB
    on 29/09 and twenty of them had piled up: 1,1 GB in a profile, on a machine whose disk was the very thing being
    watched. Growth has to be bounded wherever it happens, and here the bound is simple -- the three most recent
    copies of that account, the rest deleted.
#>
$garde = 3
foreach ($vieux in @(Get-ChildItem -LiteralPath (Split-Path $target -Parent) -Directory -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -like ($account + '-*') } |
                     Sort-Object Name -Descending | Select-Object -Skip $garde)) {
    try { Remove-Item -LiteralPath $vieux.FullName -Recurse -Force -ErrorAction Stop } catch { }
}

Write-Log -Backend $backend -Name 'diag' -Message (Get-Label 'diag-account-logs.journaux-du-compte-rapatries' $account $nb)

<#
    AND THE END OF THE LAST LOG, IN THE ANSWER.

    Fetching files answers "I want to keep everything"; the everyday question is "what has just failed?". So we
    also return the last lines of the most recent log: the one we were going to open first anyway.
#>
$dernier = @(Get-ChildItem -LiteralPath $target -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1)
$fin = @()
if ($dernier.Count) {
    try { $fin = @(Get-Content -LiteralPath $dernier[0].FullName -Encoding UTF8 -Tail 60 -ErrorAction Stop) } catch { }
}

@{
    message = ("Journaux du compte " + $account + " rapatries : " + $nb + " fichier(s).")
    result  = @{ ok = $true; path = $target; files = $nb
                 last = $(if ($dernier.Count) { $dernier[0].Name } else { $null })
                 tail = $fin }
}
