<#
.SYNOPSIS
    Verifie le contrat des sondes -- en n'executant que ce qui doit l'etre.

.DESCRIPTION
    POURQUOI CE SCRIPT EXISTE
    Le parseur PowerShell valide la SYNTAXE, pas l'execution. Un parametre passe deux fois
    (« parameter 'FixAction' is specified more than once ») franchit le parseur sans un
    mot, puis fait echouer la sonde a l'execution : la carte disparait du tableau de bord
    sans que rien ne le signale. C'est arrive le 2026-08-24 sur la sonde reseau, livree et
    annoncee comme faite.

    POURQUOI IL N'EXECUTE PAS TOUT A CHAQUE FOIS
    Une passe complete coute une vingtaine de secondes, dont huit pour la seule sonde du
    verrou. Payer ce prix pour valider une ligne de la sonde disque decourage de valider
    tout court -- et un garde-fou qu'on n'appelle plus ne garde rien.

    La regle est donc : UNE SONDE MODIFIEE EST TOUJOURS EXECUTEE. Les autres, si elles sont
    couteuses, voient leur contrat verifie sur leur DERNIERE SORTIE REELLE, enregistree ici
    meme (empreinte du fichier + horodatage). Des que le fichier change, l'enregistrement
    est perime et la sonde repasse a l'execution : on ne valide jamais du code non execute
    (D50bis).

    Le seuil de « couteuse » n'est pas une liste tenue a la main : c'est la duree MESUREE
    lors de la derniere execution reelle. Le garde-fou se calibre seul.

.PARAMETER Only
    Motifs de selection : nom de sonde ou nom de module ('net', 'lock.probe.ps1',
    'windows-update'). Ce qui est selectionne est TOUJOURS execute pour de vrai.
    C'est la boucle de developpement : on valide ce qu'on vient d'ecrire, pas toute l'app.

.PARAMETER All
    Execute toutes les sondes, sans exception. C'est la passe d'avant-livraison.

.PARAMETER HeavyMs
    Au-dela de cette duree mesuree, une sonde inchangee est verifiee sur enregistrement
    plutot que reexecutee. Defaut : 1000 ms.

.EXAMPLE
    pwsh -File .\scripts\check-probes.ps1 -Only net
    Boucle de dev : la sonde reseau et elle seule, executee.

.EXAMPLE
    pwsh -File .\scripts\check-probes.ps1 -Only windows-update
    La sonde touchee et ses voisines de module -- les regressions proches.

.EXAMPLE
    pwsh -File .\scripts\check-probes.ps1
    Passe courante : les sondes rapides executees, les couteuses inchangees verifiees sur
    leur derniere sortie reelle.

.EXAMPLE
    pwsh -File .\scripts\check-probes.ps1 -All
    Passe complete d'avant-livraison.

.NOTES
    LECTURE SEULE cote systeme : aucune action n'est declenchee. Seuls l'enregistrement des
    contrats (var/cache/probe-contract.json) et le journal des passages sont ecrits.
    Codes de retour : 0 = tout est conforme ; 1 = au moins un manquement.
#>
[CmdletBinding()]
param(
    [string[]]$Only,
    [switch]$All,
    [int]$HeavyMs = 1000
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')

$backendRoot = Join-Path $repoRoot 'apps/backend-pode'
$probesDir   = Join-Path $backendRoot 'probes'
$actionsDir  = Join-Path $backendRoot 'actions'
$actionsConnues = @(Get-ChildItem -Path $actionsDir -Filter '*.action.ps1' -File |
                    ForEach-Object { $_.Name -replace '\.action\.ps1$', '' })

$recordFile = Get-VarPath -Backend $backendRoot -Kind 'cache' -File 'probe-contract.json'

$rang = @{ ok = 0; neutral = 0; warn = 1; error = 2 }
$manquements = @()

# Empreinte du code d'une sonde. Meme principe que le codeStamp du cache d'etat : si le
# fichier bouge, tout ce qui a ete enregistre a son sujet est perime.
function Get-CodeStamp {
    param([IO.FileInfo]$File)
    '{0}-{1}' -f $File.LastWriteTimeUtc.Ticks, $File.Length
}

# Reduit la sortie d'une sonde a ce que le contrat exige -- rien de plus. Les sorties
# vivantes et les sorties enregistrees passent ensuite par le MEME controle : une seule
# regle, un seul endroit ou elle peut se tromper.
function ConvertTo-Contract {
    param($Modules)
    @(foreach ($m in @($Modules)) {
        [ordered]@{
            id      = "$($m.id)"
            status  = "$($m.status)"
            fields  = @(foreach ($c in @($m.fields)) {
                [ordered]@{
                    key       = "$($c.key)"
                    status    = "$($c.status)"
                    hasHelp   = [bool]$c.help
                    fixAction = if ($c.fixAction) { "$($c.fixAction)" } else { $null }
                    hasGuide  = [bool]$c.guide
                }
            })
            actions = @(foreach ($a in @($m.actions)) {
                [ordered]@{ id = "$($a.id)"; label = "$($a.label)" }
            })
        }
    })
}

# Les invariants du contrat (D49, D50). Rend la liste des manquements trouves.
function Test-Contract {
    param($Modules, [string]$Source)
    $trouves = @()
    foreach ($m in @($Modules)) {
        $pire = 0
        foreach ($champ in @($m.fields)) {
            $st = "$($champ.status)"
            if ($rang.ContainsKey($st) -and $rang[$st] -gt $pire) { $pire = $rang[$st] }

            if (-not $champ.hasHelp) {
                $trouves += "{0} -- {1} / {2} : le champ n'a pas d'aide" -f $Source, $m.id, $champ.key
            }
            # D66 : une resolution est TOUJOURS un bouton. Un guide explique, il ne
            # resout pas -- « Piste : lancez telle commande en administrateur » laissait
            # l'utilisateur faire le travail a la main (constate sur les compteurs GPU).
            # Ce qu'il fait varie selon le cas : reparer, ou ouvrir l'outil Windows qui
            # convient. Ce qui ne se resout pas ne s'alerte pas : c'est neutre.
            if (($st -eq 'warn' -or $st -eq 'error') -and -not $champ.fixAction) {
                $trouves += "{0} -- {1} / {2} : en '{3}' sans BOUTON de resolution (D66)" -f $Source, $m.id, $champ.key, $st
            }
            if ($champ.fixAction -and $actionsConnues -notcontains "$($champ.fixAction)") {
                $trouves += "{0} -- {1} / {2} : renvoie a l'action inconnue '{3}'" -f $Source, $m.id, $champ.key, $champ.fixAction
            }
        }
        $stMod = "$($m.status)"
        if ($rang.ContainsKey($stMod) -and $rang[$stMod] -gt $pire) {
            $trouves += "{0} -- {1} : statut '{2}' alors que le pire champ est plus bas (D49)" -f $Source, $m.id, $stMod
        }
        foreach ($a in @($m.actions)) {
            if ("$($a.label)" -match [char]0x2026 + '\s*$') {
                $trouves += "{0} -- {1} / {2} : libelle au repos avec points de suspension (D50)" -f $Source, $m.id, $a.id
            }
        }
    }
    return $trouves
}

# --- Enregistrement des contrats deja verifies -------------------------------
$record = @{}
if (Test-Path -LiteralPath $recordFile) {
    try {
        $j = Get-Content $recordFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($pr in $j.PSObject.Properties) { $record[$pr.Name] = $pr.Value }
    } catch { }
}

# --- Selection ---------------------------------------------------------------
$sondes = @(Get-ChildItem -Path $probesDir -Recurse -Filter '*.probe.ps1' -File | Sort-Object FullName)
if ($Only) {
    $motifs = $Only
    $retenues = @($sondes | Where-Object {
        $nom    = $_.Name
        $base   = $nom -replace '\.probe\.ps1$', ''
        $module = Split-Path (Split-Path $_.FullName -Parent) -Leaf
        @($motifs | Where-Object { $base -like $_ -or $nom -like $_ -or $module -like $_ }).Count -gt 0
    })
    if ($retenues.Count -eq 0) {
        Write-Host ("Aucune sonde ne correspond a : {0}" -f ($motifs -join ', ')) -ForegroundColor Red
        Write-Host ("Sondes disponibles : {0}" -f (($sondes | ForEach-Object { $_.Name -replace '\.probe\.ps1$','' }) -join ', '))
        exit 1
    }
    $sondes = $retenues
}

# --- Passe -------------------------------------------------------------------
$executees = 0; $surEnregistrement = 0; $modules = 0
$lignes = @()

foreach ($f in $sondes) {
    $stamp     = Get-CodeStamp -File $f
    $ancien    = $record[$f.Name]
    $inchangee = ($ancien -and "$($ancien.codeStamp)" -eq $stamp)
    $couteuse  = ($ancien -and [int]$ancien.ms -ge $HeavyMs)

    # Une sonde explicitement demandee, ou modifiee, ou jamais enregistree, est EXECUTEE.
    $doitExecuter = $All -or $Only -or -not $inchangee -or -not $couteuse

    if ($doitExecuter) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $rendus = $null
        try { $rendus = & $f.FullName }
        catch {
            $sw.Stop()
            Write-ProbeRun -Backend $backendRoot -Probe $f.Name -Ms $sw.ElapsedMilliseconds -Origin 'check' -Outcome 'error' -Detail $_.Exception.Message
            $manquements += "{0} : la sonde LEVE une erreur -- {1}" -f $f.Name, $_.Exception.Message
            $lignes += '  {0,-20} ECHEC a l execution' -f $f.Name
            continue
        }
        $sw.Stop()
        if (-not $rendus) {
            Write-ProbeRun -Backend $backendRoot -Probe $f.Name -Ms $sw.ElapsedMilliseconds -Origin 'check' -Outcome 'empty'
            $manquements += "$($f.Name) : la sonde ne rend AUCUN module"
            $lignes += '  {0,-20} ECHEC : aucun module' -f $f.Name
            continue
        }
        $contrat = ConvertTo-Contract -Modules $rendus
        Write-ProbeRun -Backend $backendRoot -Probe $f.Name -Ms $sw.ElapsedMilliseconds -Origin 'check' -Outcome 'ok' -Modules @($contrat).Count
        $manquements += Test-Contract -Modules $contrat -Source $f.Name
        $modules += @($contrat).Count
        $executees++
        $lignes += '  {0,-20} execute   {1,6:N0} ms   {2} module(s)' -f $f.Name, $sw.ElapsedMilliseconds, @($contrat).Count

        $record[$f.Name] = [ordered]@{
            at        = [datetime]::UtcNow.ToString('o')
            codeStamp = $stamp
            ms        = [int]$sw.ElapsedMilliseconds
            modules   = $contrat
        }
    }
    else {
        $contrat = $ancien.modules
        $manquements += Test-Contract -Modules $contrat -Source "$($f.Name) (sur enregistrement)"
        $modules += @($contrat).Count
        $surEnregistrement++
        $age = ''
        $at = ConvertTo-UtcDate $ancien.at
        if ($at) {
            $h = ([datetime]::UtcNow - $at).TotalHours
            $age = if ($h -lt 1)      { "il y a moins d une heure" }
                   elseif ($h -lt 48) { 'il y a {0:N0} h' -f $h }
                   else               { 'il y a {0:N0} j' -f ($h / 24) }
        }
        $lignes += '  {0,-20} inchangee, verifiee sur sa sortie {1} ({2:N0} ms economisees)' -f $f.Name, $age, [int]$ancien.ms
    }
}

try {
    ($record | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $recordFile -Encoding UTF8
} catch {
    Write-Host "Note : l enregistrement des contrats n a pas pu etre ecrit -- la prochaine passe reexecutera tout." -ForegroundColor DarkYellow
}

# --- Garde-fou : AUCUN CARACTERE DE CONTROLE dans les sources -----------------
#
# Le piege le plus couteux de ce projet, rencontre sept fois en une journee : un
# antislash disparait a l'ecriture et laisse un caractere de controle. « \var » devient
# 0x0B, « \7 » devient 0x07, « \t » une tabulation. Le fichier reste valide, le parseur
# ne dit rien, et un chemin ne designe soudain plus rien -- silencieusement. Deux cas
# vecus : un inventaire de comptes toujours vide, et un diagnostic qui repondait
# « ce compte n'a jamais ouvert de session » quoi qu'il arrive.
#
# On le detecte ici, ou ca coute une seconde, plutot qu'en production ou ca coute une
# soiree. Seul l'echappement ESC (0x1B) est tolere : il sert a filtrer les codes ANSI.
$dossiersSources = @('apps', 'scripts', 'config', 'docs')
$interdits = @()
foreach ($d in $dossiersSources) {
    $racineD = Join-Path $repoRoot $d
    if (-not (Test-Path -LiteralPath $racineD)) { continue }
    $fichiers = Get-ChildItem -LiteralPath $racineD -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @('.ps1', '.psd1', '.psm1', '.html', '.md', '.json', '.cmd') -and
                               $_.FullName -notmatch '\\var\\' -and $_.FullName -notmatch '\\dist\\' }
    foreach ($f in $fichiers) {
        $texte = $null
        try { $texte = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop } catch { continue }
        if (-not $texte) { continue }
        # 0x1B (ESC) exclu : volontaire. 0x09/0x0A/0x0D : tabulation et fins de ligne.
        if ($texte -match "[\u0000-\u0008\u000B\u000C\u000E-\u001A\u001C-\u001F]") {
            $ligne = 0
            foreach ($l in ($texte -split "`r?`n")) {
                $ligne++
                if ($l -match "[\u0000-\u0008\u000B\u000C\u000E-\u001A\u001C-\u001F]") {
                    $interdits += ("{0}:{1}" -f $f.FullName.Substring($repoRoot.Length + 1), $ligne)
                }
            }
        }
    }
}
foreach ($i in $interdits) {
    $manquements += "caractere de controle dans une source (antislash mange ?) -- $i"
}

# --- Verdict -----------------------------------------------------------------
$lignes | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Host ("{0} sonde(s) executee(s), {1} verifiee(s) sur enregistrement, {2} module(s) au total." -f $executees, $surEnregistrement, $modules)
if ($surEnregistrement -gt 0) {
    Write-Host "Une sonde verifiee sur enregistrement n a PAS ete reexecutee : son fichier est inchange depuis." -ForegroundColor DarkGray
    Write-Host "Passe complete avant livraison : -All" -ForegroundColor DarkGray
}

if ($manquements.Count -eq 0) {
    Write-Host "Tous les invariants sont respectes." -ForegroundColor Green
    exit 0
}
Write-Host ("{0} manquement(s) :" -f $manquements.Count) -ForegroundColor Red
$manquements | ForEach-Object { Write-Host "  - $_" }
exit 1
