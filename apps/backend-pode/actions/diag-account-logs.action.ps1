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

$compte = if ($Params -and $Params.account) { "$($Params.account)" } else { $null }
if (-not $compte) { return @{ message = "Aucun compte precise."; result = @{ ok = $false } } }

# Le compte doit exister sur CETTE machine : on ne va pas lire un chemin quelconque.
$connu = Get-AccountByName -Name $compte
if (-not $connu) { return @{ message = "Compte inconnu sur cette machine : $compte"; result = @{ ok = $false } } }

$profil = Join-Path (Join-Path $env:SystemDrive 'Users') $compte
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
    return @{ message = "Le compte $compte n'a pas encore de données Vigie : il n'a jamais ouvert de session avec Vigie active."
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
$cible = Join-Path (Join-Path $diagRoot 'diag') ($compte + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $cible -Force | Out-Null

$nb = 0
$logs = Join-Path $source 'log'
if (Test-Path -LiteralPath $logs) {
    foreach ($f in @(Get-ChildItem -LiteralPath $logs -File -ErrorAction SilentlyContinue)) {
        Copy-Item -LiteralPath $f.FullName -Destination $cible -Force
        $nb++
    }
}

# Un resume de l'etat : ce qui existe, quel poids, quelle fraicheur. C'est ce qui repond a
# « son Vigie tourne-t-il, et depuis quand ? » sans rien devoiler du contenu.
$resume = @("Compte    : $compte", "Profil    : $profil", "Donnees   : $source",
            "Releve le : $(Get-Date -Format 's')", "")
foreach ($sous in @('cache','log','history','secrets')) {
    $d = Join-Path $source $sous
    if (-not (Test-Path -LiteralPath $d)) { $resume += ("{0,-9} : absent" -f $sous); continue }
    $f = @(Get-ChildItem -LiteralPath $d -File -Recurse -ErrorAction SilentlyContinue)
    $taille = ($f | Measure-Object Length -Sum).Sum
    $recent = ($f | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    $resume += ("{0,-9} : {1} fichier(s), {2}, dernier ecrit {3}" -f $sous, $f.Count,
                (Format-ByteSize ([long]$taille)), $(if ($recent) { $recent.ToString('s') } else { '-' }))
}
$resume += ""
$resume += "Le jeton d'API n'est pas copie (secrets/), volontairement."
$resume -join [Environment]::NewLine | Set-Content -LiteralPath (Join-Path $cible 'resume.txt') -Encoding UTF8

Write-Log -Backend $backend -Name 'diag' -Message (Get-Label 'diag-account-logs.journaux-du-compte-rapatries' $compte $nb)

<#
    ET LA FIN DU DERNIER JOURNAL, DANS LA REPONSE.

    Rapatrier des fichiers repond a « je veux tout garder » ; la question courante est
    « qu'est-ce qui vient d'echouer ? ». On rend donc aussi les dernieres lignes du
    journal le plus recent : celui qu'on allait ouvrir en premier de toute facon.
#>
$dernier = @(Get-ChildItem -LiteralPath $cible -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1)
$fin = @()
if ($dernier.Count) {
    try { $fin = @(Get-Content -LiteralPath $dernier[0].FullName -Encoding UTF8 -Tail 60 -ErrorAction Stop) } catch { }
}

@{
    message = ("Journaux du compte " + $compte + " rapatries : " + $nb + " fichier(s).")
    result  = @{ ok = $true; path = $cible; files = $nb
                 last = $(if ($dernier.Count) { $dernier[0].Name } else { $null })
                 tail = $fin }
}
