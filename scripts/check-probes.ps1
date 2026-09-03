# @author Florent HAZARD <f.hazard@sowapps.com>
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

    # Plafond par sonde, en secondes. Au-dela, elle est declaree bloquee et le controle
    # continue : un verificateur ne doit jamais etre celui qui fait attendre.
    [int]$ProbeTimeoutSec = 180,
    [switch]$All,
    [int]$HeavyMs = 1000
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')   # le meme affichage que partout
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
                    # La VALEUR et le GENRE sont retenus : sans eux, un controle sur ce
                    # qui s'affiche regarde du vide. Le controle des majuscules est passe
                    # au travers pour cette raison, et un piege pose expres n'a pas ete
                    # attrape -- c'est en le posant qu'on l'a su.
                    value     = "$($c.value)"
                    kind      = "$($c.kind)"
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
            # MAJUSCULE INITIALE (regle utilisateur, 27/08 : « tu oublies souvent ces
            # majuscules »). Une valeur affichee est une reponse, pas un fragment de
            # phrase : « À jour », pas « à jour ». Les DONNEES en sont exemptees --
            # un numero de version (v0.1.4), un nom de fichier (ext4.vhdx), un chemin
            # ou un nom de processus s'ecrivent comme ils sont.
            #
            # ATTENTION a l'exemption : « tout ce qui n'a ni espace ni majuscule » etait
            # trop large -- le mot « aucun » y entrait, et le garde-fou laissait passer
            # exactement ce qu'il devait attraper (essaye, et pris en flagrant delit).
            # Un identifiant porte un chiffre ou un separateur ; un mot francais, non.
            $val = "$($champ.value)"
            $ressembleAUneDonnee = ($val -match '^v?[0-9]') -or ($val -match '[\/]') -or
                                   ($val -match '^[a-z0-9._-]*[0-9._-][a-z0-9._-]*$') -or
                                   ($val -match '^[a-z0-9_-]+\.[a-z0-9]{2,5}\s')
            if ($champ.kind -eq 'text' -and $val -cmatch '^[a-zàâäéèêëîïôöùûüç]' -and -not $ressembleAUneDonnee) {
                $trouves += "{0} -- {1} / {2} : valeur affichee sans majuscule initiale (« {3} »)" -f $Source, $m.id, $champ.key, $val
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
        Write-Fail (Get-Label 'check-probes.aucune-sonde-ne-correspond' ($motifs -join ', '))
        Write-Info (Get-Label 'check-probes.sondes-disponibles' (($sondes | ForEach-Object { $_.Name -replace '\.probe\.ps1$','' }) -join ', '))
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
        $job = $null
        <#
            UNE SONDE QUI NE REND PAS LA MAIN EST UN MANQUEMENT, PAS UNE ATTENTE.

            Le 01/09, ce controle est reste bloque VINGT-QUATRE MINUTES : la sonde du
            deploiement interroge le clone git, et une installation tournait au meme
            moment. Sans limite, un verificateur devient lui-meme le probleme -- on ne
            sait plus s'il travaille ou s'il est mort.

            La sonde tourne donc dans un processus a part, avec un plafond. Au-dela, on le
            dit et on passe a la suivante : le rapport reste complet, et la cause est
            nommee.
        #>
        try {
            $job = Start-Job -ScriptBlock { param($path) & $path } -ArgumentList $f.FullName
            if (Wait-Job -Job $job -Timeout $ProbeTimeoutSec) {
                $rendus = Receive-Job -Job $job -ErrorAction Stop
            } else {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                throw ("la sonde n'a pas rendu la main en " + $ProbeTimeoutSec + " s")
            }
        }
        catch {
            $sw.Stop()
            Write-ProbeRun -Backend $backendRoot -Probe $f.Name -Ms $sw.ElapsedMilliseconds -Origin 'check' -Outcome 'error' -Detail $_.Exception.Message
            $manquements += "{0} : la sonde LEVE une erreur -- {1}" -f $f.Name, $_.Exception.Message
            $lignes += '  {0,-20} ECHEC a l execution' -f $f.Name
            continue
        }
        finally { if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } }
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
    Write-Info (Get-Label 'check-probes.note-enregistrement-des-contrats')
}

# --- Garde-fou : LES LIBELLES VISIBLES PORTENT LEURS ACCENTS ------------------
#
# Regle du projet (disciplines.md), rappelee le 27/08 : « il ne devrait jamais manquer
# les accents, tout doit etre en UTF-8 ». Les commentaires du code sont ecrits sans
# accents -- c'est assume et sans consequence -- mais TOUT ce qui s'affiche doit etre
# ecrit en francais correct. La carte annoncait « deployee avant le suivi des commits »
# et « ecart inconnu ».
#
# On ne verifie que les chaines DESTINEES A L'ECRAN : celles qui suivent -Value, -Label,
# -Help, -Guide, -BusyLabel, ou un « message = ». Le reste (chemins, identifiants, noms
# de fichiers) n'est pas concerne.
#
# La liste est volontairement COURTE : uniquement des mots qui, dans cette application,
# ne s'ecrivent jamais sans accent. Un garde-fou qui crie a tort finit ignore.
# Mots ECARTES apres essai, parce qu'ils s'ecrivent AUSSI sans accent en francais :
#   « active » (la protection est active), « termine » (il termine), « apres » quand il
#   s'agit d'un nom de variable. Un garde-fou qui crie a tort finit ignore -- on prefere
#   en attraper un peu moins et etre cru.
$motsAccentues = @(
    'deploiement', 'deployee', 'deploye', 'redeploie',
    'echec', 'echoue', 'ecart', 'elevee',
    'reparee', 'terminee', 'activee',
    'releve', 'depot', 'parametre', 'parametres', 'verifiee',
    'demarrage', 'demarre', 'tache', 'taches', 'interpreteur',
    'reglage', 'reglages', 'systeme', 'securite', 'memoire', 'donnees',
    'operation', 'derniere', 'deja', 'privilege', 'numero'
)
$motifAccents = '(?i)\b(' + ($motsAccentues -join '|') + ')\b'
$sansAccent = @()
foreach ($d in @('probes', 'actions', 'lib', 'workers')) {
    $racineD = Join-Path $backendRoot $d
    if (-not (Test-Path -LiteralPath $racineD)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $racineD -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue)) {
        $ligne = 0
        foreach ($l in (Get-Content -LiteralPath $f.FullName -Encoding UTF8)) {
            $ligne++
            # Un commentaire n'est pas affiche : on le laisse tranquille.
            if ($l -match '^\s*#') { continue }
            # LE TIRET DOIT COMMENCER UN PARAMETRE. Sans cette borne, « Get-Label » contient
            # « -Label » : l'invariant lisait la CLE d'un libelle -- volontairement en ASCII --
            # et reclamait des accents dessus.
            foreach ($m in [regex]::Matches($l, '(?:(?<![\w-])(?:-Value|-Label|-Help|-Guide|-BusyLabel)|message\s*=)\s*("[^"]*"|''[^'']*'')')) {
                # Les VARIABLES interpolees ne sont pas du texte affiche tel quel :
                # « $($apres.noAutoUpdate) » n'est pas le mot « apres ». On les retire
                # avant de juger.
                $texte = [regex]::Replace($m.Groups[1].Value, '\$\([^)]*\)|\$[A-Za-z_][A-Za-z0-9_.]*', ' ')
                if ($texte -match $motifAccents) {
                    $sansAccent += ("{0}:{1} -- « {2} »" -f $f.Name, $ligne, $Matches[1])
                }
            }
        }
    }
}
foreach ($x in $sansAccent) {
    $manquements += "libelle visible sans accent -- $x"
}

# --- Garde-fou : AUCUN APPEL EXTERNE QUI PEUT DEMANDER UNE SAISIE -------------
#
# Une installation tourne sans personne devant. Un outil externe qui pose une question
# et attend sur l'entree standard la fige INDEFINIMENT, sans message : on croit a un
# plantage, ou pire on n'y croit pas et on attend.
#
# Constate le 29/08 : « schtasks /change /RU <compte> » sans /RP demande le mot de passe
# du compte. L'installation est restee bloquee 28 secondes -- le temps que quelqu'un
# appuie sur Entree, ce qui a fourni un mot de passe VIDE. L'erreur qui suivait etait
# avalee par un « $null = $out ».
#
# La liste est volontairement COURTE et precise : on ne devine pas quel outil pose des
# questions, on ajoute ceux qui nous ont deja coute une soiree.
$interactifs = @()
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1','*.cmd' -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    # « var » contient le CLONE DU SERVICE (D112) : une copie entiere du depot, qu'on
    # jugerait deux fois -- et dont on ne corrige rien, puisqu'elle se regenere.
    if ($rel -like '.claude/*' -or $rel -like 'dist/*' -or $rel -like 'local/*' -or $rel -like '*/var/*') { continue }
    # Ce fichier-ci CITE les motifs qu'il traque : se juger soi-meme n'a pas de sens,
    # et un verificateur qui se denonce apprend a son lecteur a l'ignorer.
    if ($rel -like '.claude/*' -or $rel -like 'dist/*' -or $rel -like 'local/*' -or
        $rel -eq 'scripts/check-probes.ps1') { continue }
    $lineNo = 0
    foreach ($l in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $lineNo++
        if ($l -match '^\s*#') { continue }
        # schtasks qui change le compte d'execution SANS fournir le mot de passe.
        if ($l -match 'schtasks' -and $l -match '/RU\b' -and $l -notmatch '/RP\b') {
            $interactifs += ("{0}:{1} -- schtasks /RU sans /RP : demande le mot de passe et attend" -f $rel, $lineNo)
        }
        # Read-Host dans un script qui tourne SANS PERSONNE DEVANT.
        #
        # L'exception, et sa raison : install-dev.ps1 est un outil de developpement, lance
        # a la main. Sa question graphique peut echouer (pas d'interface disponible) ; le
        # repli en ligne de commande s'adresse alors a quelqu'un qui EST devant. Le lui
        # interdire reviendrait a lui retirer son seul repli.
        $unattended = ($rel -like 'scripts/*' -or $rel -like 'apps/backend-pode/*') -and
                        $rel -ne 'scripts/dev/install-dev.ps1'
        if ($l -match '\bRead-Host\b' -and $unattended) {
            $interactifs += ("{0}:{1} -- Read-Host : rien ne repondra si personne n'est devant" -f $rel, $lineNo)
        }
    }
}
foreach ($x in $interactifs) { $manquements += "appel qui attend une saisie -- $x" }

# --- Garde-fou : PAS DE TEXTE ACCENTUE EN ARGUMENT D'UN AUTRE PROCESSUS -------
#
# Un texte accentue passe en argument d'un AUTRE processus traverse la ligne de commande,
# donc la page de code du moment : « securite » y devient « sIcuritI » (constate le 29/08
# sur la fenetre de fin d'installation). Aucun encodage de FICHIER n'y peut rien -- le mal
# se fait ENTRE les deux processus.
#
# show-confirm.ps1 sait lire les libelles lui-meme : on lui passe des CLES (-TitleKey,
# -SummaryKey, -DetailsKey), qui sont de l'ASCII pur. Lui passer -Title, -Summary ou
# -Details en clair, c'est reprendre le chemin qui abime les accents.
$plainText = @()
$plainParams = @('Title', 'Summary', 'Details')
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($rel -like '.claude/*' -or $rel -like 'dist/*' -or $rel -like 'local/*' -or $rel -like '*/var/*') { continue }
    # Le porteur du mecanisme et ce verificateur citent forcement ces noms.
    if ($rel -eq 'scripts/lib/show-confirm.ps1' -or $rel -eq 'scripts/check-probes.ps1') { continue }
    $body = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $body) { continue }
    if ($body -notmatch 'show-confirm') { continue }
    foreach ($nom in $plainParams) {
        # « -Title » suivi d'autre chose que « Key » : c'est la forme en clair.
        # LE TIRET DOIT COMMENCER UN PARAMETRE : « Write-Title » contient « -Title ».
        # Le nom doit FINIR la : « -DetailsArg » n'est pas « -Details ».
        if ($body -match ('(?<![\w])-' + $nom + '(?![\w])')) {
            $plainText += ("{0} -- « -{1} » en clair : passer « -{1}Key »" -f $rel, $nom)
        }
    }
}
foreach ($x in $plainText) { $manquements += "texte accentue en argument -- $x" }

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

# --- Garde-fou : PERSONNE NE CALCULE UN CHEMIN DE DONNEES A LA MAIN -----------
#
# Le programme installe vit dans Program Files, et ce dossier est en LECTURE SEULE
# (D97) : seules les donnees du compte courant sont ecrites, dans son profil. Un chemin
# « var/... » assemble a la main court-circuite cette regle et ecrit a cote du programme.
#
# Ce n'est pas une precaution theorique : c'est exactement ce qui empechait Vigie de
# demarrer sur un compte standard. Le tray calculait « $PSScriptRoot/var/log », Windows
# refusait la creation du dossier, et le script mourait a sa deuxieme ligne -- sans
# journal, puisque le journal etait justement ce qu'il essayait de creer.
#
# Get-VarPath et Get-VarRoot savent ou vont les donnees. Personne d'autre.
$horsRegle = @()
foreach ($d in @('apps', 'scripts')) {
    $racineD = Join-Path $repoRoot $d
    if (-not (Test-Path -LiteralPath $racineD)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $racineD -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue)) {
        # common.ps1 EST l'implementation de la regle : c'est le seul endroit ou ces
        # chemins se construisent.
        if ($f.Name -eq 'common.ps1') { continue }
        $i = 0
        foreach ($ligne in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            $i++
            if ($ligne -match '^\s*#') { continue }
            if (($ligne -match 'Join-Path') -and ($ligne -match 'var[/\\](log|run|cache|secrets|history)')) {
                $horsRegle += ("{0}:{1}" -f (Resolve-Path -LiteralPath $f.FullName -Relative), $i)
            }
        }
    }
}
foreach ($x in $horsRegle) {
    $manquements += "chemin de donnees calcule a la main (utiliser Get-VarPath) -- $x"
}

# --- Garde-fou : « QUI EXECUTE » N'EST PAS « QUI DEMANDE » --------------------
#
# $env:USERNAME rend le compte qui EXECUTE le processus. Tant que l'app serveur tournait
# sous le compte de quelqu'un, il tombait juste PAR ACCIDENT. Depuis qu'elle tourne en
# service sous « VigieService », tout endroit qui l'employait pour dire « la personne
# devant l'ecran » designe le service : la carte Comptes a affiche « VOUS » sur
# VigieService et l'a sorti de la liste des comptes techniques (constate le 29/08).
#
# Trois fonctions, trois sens, et le choix devient conscient :
#   Get-ProcessAccount   -- qui execute (vrai pour l'app cliente et les scripts)
#   Get-RequesterAccount -- qui demande, ou $null si personne n'est identifie
#   Get-ActionRequester  -- qui demande, avec un repli, pour SIGNER le journal d'audit
$rawUserVar = @()
foreach ($d in @('apps', 'scripts')) {
    $racineD = Join-Path $repoRoot $d
    if (-not (Test-Path -LiteralPath $racineD)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $racineD -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue)) {
        # common.ps1 EST l'implementation de la regle : Get-ProcessAccount y vit.
        if ($f.Name -eq 'common.ps1') { continue }
        $i = 0
        foreach ($ligne in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            $i++
            if ($ligne -match '^\s*#') { continue }
            # LE MOTIF S'ECRIT EN MORCEAUX, sinon ce fichier se denonce lui-meme -- comme
            # les motifs de mojibake de check-encoding.
            if ($ligne -match ('\$env:' + 'USER' + 'NAME')) {
                $rawUserVar += ("{0}:{1}" -f (Resolve-Path -LiteralPath $f.FullName -Relative), $i)
            }
        }
    }
}
foreach ($x in $rawUserVar) {
    $manquements += (('$env:' + 'USER' + 'NAME') +
                     " en clair (Get-ProcessAccount, ou Get-RequesterAccount si c'est la personne) -- " + $x)
}

# --- Guard rail: A COMMAND LINE IS BUILT BY THE TOOL, NEVER BY HAND -----------
#
# Start-Process joins -ArgumentList with spaces and quotes NOTHING, so a bare path dies on
# "C:\Program is not a script" -- silently, the caller believing it started something
# (measured on 02/09 on the gaming resident). Wrapping the value by hand looks like the fix
# and is not: a path ending with a backslash then escapes its own closing quote and swallows
# the argument that follows (measured on 03/09).
#
# So neither fault is left to attention: Start-ChildProcess quotes, once, for everyone
# (D116), and nothing else builds a command line. Two refusals:
#   - Start-Process carrying arguments anywhere but inside the tool itself;
#   - a value wrapped by hand, whatever the world -- the call operator and .NET's
#     ArgumentList quote by themselves, so hand-wrapping there ADDS real quote characters;
#   - ProcessStartInfo.Arguments, a command line written as ONE string: its ArgumentList
#     sibling takes the values one by one and quotes them itself.
#
# The two patterns are ASSEMBLED rather than written: spelled out, this file would refuse
# itself, and a checker that flags its own text teaches nothing.
$handBuilt  = @()
$quoteChar  = [string][char]34
$apostrophe = [string][char]39
$handQuote  = $apostrophe + $quoteChar + $apostrophe + '\s*\+'
$startVerb  = 'Start' + '-Process'
$withArgs   = '\b' + $startVerb + '\b\s+(?:-FilePath\s+)?(?!-)[^\s;|}]+\s+(?![-;}|#])[^\s;|}]'
foreach ($d in @('apps', 'scripts')) {
    $rootDir = Join-Path $repoRoot $d
    if (-not (Test-Path -LiteralPath $rootDir)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $rootDir -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue)) {
        if ($f.FullName -like ('*' + [IO.Path]::DirectorySeparatorChar + 'var' + [IO.Path]::DirectorySeparatorChar + '*')) { continue }
        $relative = (Resolve-Path -LiteralPath $f.FullName -Relative)
        $i = 0
        $currentFunction = ''
        $inHereString = $false
        $inBlockComment = $false
        foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            $i++
            # A here-string carries GENERATED source, not code that runs here: what it holds
            # was quoted at generation time, by the same tool. One line can close one and
            # open the next, so we test the closing FIRST and the opening after.
            if ($inHereString) {
                if ($line -match '^\s*[''"]@') { $inHereString = $false } else { continue }
            }
            if ($inBlockComment) {
                if ($line -match '#>') { $inBlockComment = $false }
                continue
            }
            if ($line -match '<#' -and $line -notmatch '#>') { $inBlockComment = $true; continue }
            if ($line -match '^\s*#') { continue }
            if ($line -match '@[''"]\s*$') { $inHereString = $true; continue }
            if ($line -match '^\s*function\s+([A-Za-z0-9-]+)') { $currentFunction = $Matches[1] }

            if ($line -match '\.Arguments\s*=') {
                $handBuilt += ("ligne de commande ecrite a la main (ArgumentList.Add, D116) -- {0}:{1}" -f $relative, $i)
            }
            if ($line -match $handQuote) {
                $handBuilt += ("valeur citee a la main (ConvertTo-ProcessArgument, ou rien du tout) -- {0}:{1}" -f $relative, $i)
            }
            # The single legitimate call is the one INSIDE the tool.
            if ($currentFunction -eq 'Start-ChildProcess') { continue }
            if ($line -notmatch ('\b' + $startVerb + '\b')) { continue }
            # Opening a URL or a program with NO argument builds no command line: nothing
            # to get wrong, and forcing the tool there would only add noise.
            if (($line -notmatch '-ArgumentList') -and ($line -notmatch $withArgs)) { continue }
            $handBuilt += ("{0} avec des arguments (Start-ChildProcess, D116) -- {1}:{2}" -f $startVerb, $relative, $i)
        }
    }
}
foreach ($x in $handBuilt) { $manquements += $x }

# --- Guard rail: NOTHING BETWEEN A CONTINUATION AND ITS PARAMETER -------------
#
# A comment slipped after a continuation backtick CUTS the command: the next line becomes a
# command of its own, and PowerShell answers "the term '-Impact' is not recognized". Fell
# for it twice -- deployment.probe.ps1 on 29/08, firewall.probe.ps1 on 02/09 -- and both
# times the probe was broken in production.
$cutCommand = @()
foreach ($d in @('apps', 'scripts')) {
    $rootDir = Join-Path $repoRoot $d
    if (-not (Test-Path -LiteralPath $rootDir)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $rootDir -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue)) {
        if ($f.FullName -like ('*' + [IO.Path]::DirectorySeparatorChar + 'var' + [IO.Path]::DirectorySeparatorChar + '*')) { continue }
        $lines = @(Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)
        for ($i = 0; $i -lt $lines.Count - 1; $i++) {
            $previous = "$($lines[$i])".Trim()
            # A comment line may end with a backtick ("`running`"): that is not a
            # continuation, and mistaking it would be a false positive.
            if ($previous -match '^#') { continue }
            if ($previous.TrimEnd() -notmatch ([char]96 + '$')) { continue }
            if ("$($lines[$i + 1])".Trim() -notmatch '^#') { continue }
            $cutCommand += ("{0}:{1}" -f (Resolve-Path -LiteralPath $f.FullName -Relative), ($i + 2))
        }
    }
}
foreach ($x in $cutCommand) {
    $manquements += ("commentaire apres une continuation : la commande est coupee -- " + $x)
}

# --- Guard rail: THE SERVER HAS NO AMBIENT USER -------------------------------
#
# HKCU, %LOCALAPPDATA%, %APPDATA%, %USERPROFILE% name the account that RUNS the code. On the
# server side that is VigieService: a hive and a profile where nobody ever installed or set
# anything. The code looks there and sees nothing -- no error, not a word.
# Measured on 01/09: games (Steam libraries, Game Bar) and WSL (default distribution) were
# read from HKCU, hence never found, whatever account was playing.
#
# What is read PER USER is read HIVE BY HIVE (Get-UserRegistryRoots, Get-AccountRegistryRoot)
# or PROFILE BY PROFILE (Get-AccountConfigDir, Get-AccountVarRoot). The rule only binds the
# server's code: the client app and the scripts do run inside somebody's session.
$ambientUser = @()
$serverRoot = Join-Path $repoRoot 'apps/backend-pode'
foreach ($f in (Get-ChildItem -LiteralPath $serverRoot -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue)) {
    # common.ps1 IS the rule's implementation; var/ is a working copy.
    if ($f.Name -eq 'common.ps1') { continue }
    if ($f.FullName -like ('*' + [IO.Path]::DirectorySeparatorChar + 'var' + [IO.Path]::DirectorySeparatorChar + '*')) { continue }
    $i = 0
    foreach ($ligne in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $i++
        if ($ligne -match '^\s*#') { continue }
        # The pattern is assembled, or this file would report itself.
        # CHAQUE morceau entre parentheses : la virgule lie plus fort que le plus, et
        # sans elles les quatre motifs se recollaient en UN SEUL, qui ne matchait rien.
        foreach ($pattern in @(('HK' + 'CU:'), ('$env:' + 'LOCALAPPDATA'), ('$env:' + 'APPDATA'), ('$env:' + 'USERPROFILE'))) {
            if ($ligne -like ('*' + $pattern + '*')) {
                $ambientUser += ("{0}:{1} -- {2}" -f (Resolve-Path -LiteralPath $f.FullName -Relative), $i, $pattern)
            }
        }
    }
}
foreach ($x in $ambientUser) {
    $manquements += ("utilisateur ambiant cote serveur (lire ruche par ruche ou profil par profil) -- " + $x)
}

# --- Garde-fou : UNE CARTE QUI PARLE DE « VOUS » SE DECLARE PerAccount --------
#
# Le rendu des sondes est mis en cache dans state-cache.json, qui est COMMUN. Une carte
# qui ecrit « (vous) », trie sur le compte courant ou n'affiche les donnees que du
# demandeur y laisse donc la reponse calculee pour UNE personne, servie ensuite a toutes
# les autres. C'est ce qui est arrive a la carte des comptes.
#
# La declaration « PerAccount = $true » dans module.psd1 donne a la sonde une entree de
# cache par compte. Elle ne se devine pas : on verifie qu'elle est la des que le code de
# la sonde regarde le demandeur.
$personalCards = @()
$probesRoot = Join-Path $repoRoot 'apps/backend-pode/probes'
foreach ($f in (Get-ChildItem -LiteralPath $probesRoot -Recurse -File -Filter '*.probe.ps1' -ErrorAction SilentlyContinue)) {
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $text) { continue }
    # LA MARQUE EST LA SOURCE, PAS LE MOT. Chercher « .current » attrapait
    # « $scan.current » -- le DOSSIER en cours d'analyse dans la carte du disque, qui
    # n'a rien de personnel. Ce qui rend une carte personnelle, c'est d'ou viennent
    # ses donnees : la liste des comptes (elle porte « vous ») ou le demandeur.
    if ($text -notmatch 'Get-ComputerAccounts' -and $text -notmatch 'Get-RequesterAccount') { continue }
    $declared = $false
    try {
        $decl = Join-Path (Split-Path $f.FullName -Parent) 'module.psd1'
        if (Test-Path -LiteralPath $decl) {
            $declared = [bool](Import-PowerShellDataFile -LiteralPath $decl -ErrorAction Stop).PerAccount
        }
    } catch { }
    if (-not $declared) { $personalCards += (Resolve-Path -LiteralPath $f.FullName -Relative) }
}
foreach ($x in $personalCards) {
    $manquements += "carte personnelle sans « PerAccount = `$true » dans son module.psd1 -- $x"
}

# --- Verdict -----------------------------------------------------------------
$lignes | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Info (Get-Label 'check-probes.sonde-executee-verifiee-sur' $executees $surEnregistrement $modules)
if ($surEnregistrement -gt 0) {
    Write-Detail (Get-Label 'check-probes.une-sonde-verifiee-sur')
    Write-Detail (Get-Label 'check-probes.passe-complete-avant-livraison')
}

if ($manquements.Count -eq 0) {
    Write-Ok (Get-Label 'check-probes.tous-les-invariants-sont')
    exit 0
}
Write-Fail (Get-Label 'check-probes.manquement' $manquements.Count)
$manquements | ForEach-Object { Write-Host "  - $_" }
exit 1
