# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- lit dans le profil d'un autre compte : Windows exige l'elevation (D65)
<# Action : rapatrie les JOURNAUX de Vigie d'un autre compte, pour diagnostic.

   Pourquoi une action et pas une elevation a la demande (choix utilisateur) : le serveur
   Vigie tourne DEJA eleve quand un administrateur l'utilise. Passer par lui evite une
   invite UAC de plus, et surtout le filtre est le meme que pour toute action sensible --
   un compte standard se voit refuser, exactement comme pour le verrou Windows Update.

   LECTURE SEULE chez le compte vise. Le jeton d'API (var/secrets) n'est JAMAIS copie :
   un secret ne se recopie pas « pour voir », et les journaux suffisent au diagnostic.

   Parametres : account = le compte a diagnostiquer. #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$account = if ($Params -and $Params.account) { "$($Params.account)" } else { $null }
if (-not $account) { return @{ message = "Aucun compte precise."; result = @{ ok = $false } } }

# Le compte doit exister sur CETTE machine : on ne va pas lire un chemin quelconque.
$connu = Get-AccountByName -Name $account
if (-not $connu) { return @{ message = "Compte inconnu sur cette machine : $account"; result = @{ ok = $false } } }

$profil = Join-Path (Join-Path $env:SystemDrive 'Users') $account
# CHEMIN CONSTRUIT PAR Join-Path, jamais ecrit en toutes lettres : cette ligne
# portait 'AppData\Local\Vigie\var' et l'antislash de « \var » a ete mange a
# l'ecriture -- il en restait un caractere de controle, donc un dossier qui n'existe
# nulle part. Le diagnostic repondait « ce compte n'a jamais ouvert de session »
# quoi qu'il arrive.
#
# L'editeur figure aussi dans le chemin depuis D72 : %LOCALAPPDATA%\Sowapps\Vigie.
# On essaie les deux, l'ancien emplacement pouvant subsister.
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
    ON RAPATRIE CHEZ CELUI QUI DEMANDE, PAS CHEZ SOI.

    La copie atterrissait dans le var de l'APP SERVEUR -- c'est-a-dire dans le profil du
    compte de service, ou une session ordinaire n'a meme pas le droit de LIRE. « Journaux
    rapatries : 62 fichiers » etait donc vrai et inutile : personne d'autre que le service
    ne pouvait les ouvrir. Constate le 31/08, en cherchant pourquoi une mise a jour avait
    echoue.

    Ils vont donc chez le demandeur, dans SON dossier de donnees Vigie, qu'il peut ouvrir
    d'un double-clic. Sans demandeur identifie -- appel hors session -- on retombe sur le
    var du serveur : c'est mieux que de ne rien copier.
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

# Un resume de l'etat : ce qui existe, quel poids, quelle fraicheur. C'est ce qui repond a
# « son Vigie tourne-t-il, et depuis quand ? » sans rien devoiler du contenu.
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
    ET LA FIN DU DERNIER JOURNAL, DANS LA REPONSE.

    Rapatrier des fichiers repond a « je veux tout garder » ; la question courante est
    « qu'est-ce qui vient d'echouer ? ». On rend donc aussi les dernieres lignes du
    journal le plus recent : celui qu'on allait ouvrir en premier de toute facon.
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
