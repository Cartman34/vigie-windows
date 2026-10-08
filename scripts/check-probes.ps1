# @author Florent HAZARD <f.hazard@sowapps.com>
<#
.SYNOPSIS
    Checks the probes' contract -- running only what has to be run.

.DESCRIPTION
    Intent: catch what the parser cannot see. A probe that parses perfectly can still fail at RUN time, and its
    card then disappears from the panel with nothing to report it. So this script runs the probes and judges their
    output against the contract (D49, D50) -- without paying the price of a full pass at every edit.

    Usage: `pwsh -File .\scripts\check-probes.ps1 -Only net` while writing a probe; with no argument before a
    commit; `-All` before a delivery. READ ONLY as far as the system is concerned: no action is triggered. The only
    things written are the record of the contracts (var/cache/probe-contract.json) and the log of the passes. Exit
    codes: 0 = everything conforms; 1 = at least one shortfall.

    WHY THIS SCRIPT EXISTS
    The PowerShell parser validates the SYNTAX, not the execution. A parameter passed twice ("parameter 'FixAction'
    is specified more than once") crosses the parser without a word, then makes the probe fail at run time: the
    card disappears from the panel with nothing to signal it. That happened on 2026-08-24 on the network probe,
    delivered and announced as done.

    WHY IT DOES NOT RUN EVERYTHING EVERY TIME
    A full pass costs some twenty seconds, eight of them for the lock probe alone. Paying that price to validate
    one line of the disc probe discourages validating at all -- and a guard nobody calls any more guards nothing.

    So the rule is: A MODIFIED PROBE IS ALWAYS RUN. The others, if they are expensive, have their contract checked
    against their LAST REAL OUTPUT, recorded here (the file's fingerprint plus a timestamp). As soon as the file
    changes, the record is stale and the probe goes back to being run: we never validate code that was not run
    (D50bis).

    The threshold for "expensive" is not a list kept by hand: it is the duration MEASURED at the last real run.
    The guard calibrates itself.

.PARAMETER Only
    Selection patterns: the name of a probe or of a module ('net', 'lock.probe.ps1', 'windows-update'). What is
    selected is ALWAYS really run. This is the development loop: one validates what one has just written, not the
    whole app.

.PARAMETER All
    Runs every probe, with no exception. This is the pre-delivery pass.

.PARAMETER HeavyMs
    Beyond this measured duration, an unchanged probe is checked against its record rather than run again.
    Default: 1000 ms.

.EXAMPLE
    pwsh -File .\scripts\check-probes.ps1 -Only net
    The dev loop: the network probe and it alone, run for real.

.EXAMPLE
    pwsh -File .\scripts\check-probes.ps1 -Only windows-update
    The probe that was touched and its neighbours in the module -- the nearby regressions.

.EXAMPLE
    pwsh -File .\scripts\check-probes.ps1
    The everyday pass: the fast probes run, the expensive unchanged ones checked against their last real output.

.EXAMPLE
    pwsh -File .\scripts\check-probes.ps1 -All
    The full pre-delivery pass.
#>


[CmdletBinding()]
param(
    [string[]]$Only,

    # A ceiling per probe, in seconds. Beyond it the probe is declared stuck and the check carries on: a checker
    # must never be the one that makes you wait.
    [int]$ProbeTimeoutSec = 180,
    [switch]$All,
    [int]$HeavyMs = 1000
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')   # the same display as everywhere
. (Join-Path $repoRoot 'apps/backend-pode/lib/common.ps1')

$backendRoot = Join-Path $repoRoot 'apps/backend-pode'
$probesDir   = Join-Path $backendRoot 'probes'
$actionsDir  = Join-Path $backendRoot 'actions'
$actionsConnues = @(Get-ChildItem -Path $actionsDir -Filter '*.action.ps1' -File |
                    ForEach-Object { $_.Name -replace '\.action\.ps1$', '' })

$recordFile = Get-VarPath -Backend $backendRoot -Kind 'cache' -File 'probe-contract.json'

$rang = @{ ok = 0; neutral = 0; warn = 1; error = 2 }
$shortfalls = @()

# The fingerprint of a probe's code. The same principle as the state cache's codeStamp: if the file moves,
# everything recorded about it is stale.
function Get-CodeStamp {
    param([IO.FileInfo]$File)
    '{0}-{1}' -f $File.LastWriteTimeUtc.Ticks, $File.Length
}

# Reduces a probe's output to what the contract demands -- nothing more. Live outputs and recorded outputs then go
# through the SAME check: one single rule, one single place where it can be wrong.
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
                    # The VALUE and the KIND are kept: without them, a check on what is displayed looks at nothing.
                    # The check on initial capitals slipped through for that reason, and a trap laid on purpose was
                    # not caught -- it is by laying it that we found out.
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

# The contract's invariants (D49, D50). Returns the list of shortfalls found.
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
            # D66: a resolution is ALWAYS a button. A guide explains, it does not resolve -- "a hint: run such a
            # command as an administrator" left the user to do the work by hand (observed on the GPU counters).
            # What it does varies with the case: repair, or open the Windows tool that fits. What cannot be
            # resolved is not alerted on: it is neutral.
            if (($st -eq 'warn' -or $st -eq 'error') -and -not $champ.fixAction) {
                $trouves += "{0} -- {1} / {2} : en '{3}' sans BOUTON de resolution (D66)" -f $Source, $m.id, $champ.key, $st
            }
            # AN INITIAL CAPITAL (the owner's rule, 27/08: "you often forget those capitals"). A displayed value is
            # an answer, not a fragment of a sentence. DATA is exempt -- a version number (v0.1.4), a file name
            # (ext4.vhdx), a path or a process name are written as they are.
            #
            # BEWARE THE EXEMPTION: "anything with neither a space nor a capital" was too wide -- a plain French
            # word fell inside it, and the guard let through exactly what it was meant to catch (tried, and caught
            # red-handed). An identifier carries a digit or a separator; a word does not.



            $val = "$($champ.value)"
            $looksLikeData = ($val -match '^v?[0-9]') -or ($val -match '[\/]') -or
                                   ($val -match '^[a-z0-9._-]*[0-9._-][a-z0-9._-]*$') -or
                                   ($val -match '^[a-z0-9_-]+\.[a-z0-9]{2,5}\s')
            if ($champ.kind -eq 'text' -and $val -cmatch '^[a-zàâäéèêëîïôöùûüç]' -and -not $looksLikeData) {
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

# --- The record of the contracts already checked ------------------------------
$record = @{}
if (Test-Path -LiteralPath $recordFile) {
    try {
        $j = Get-Content $recordFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($pr in $j.PSObject.Properties) { $record[$pr.Name] = $pr.Value }
    } catch { }
}

# --- Selection ---------------------------------------------------------------
$probes = @(Get-ChildItem -Path $probesDir -Recurse -Filter '*.probe.ps1' -File | Sort-Object FullName)
if ($Only) {
    $motifs = $Only
    $retenues = @($probes | Where-Object {
        $name    = $_.Name
        $base   = $name -replace '\.probe\.ps1$', ''
        $module = Split-Path (Split-Path $_.FullName -Parent) -Leaf
        @($motifs | Where-Object { $base -like $_ -or $name -like $_ -or $module -like $_ }).Count -gt 0
    })
    if ($retenues.Count -eq 0) {
        Write-Fail (Get-Label 'check-probes.aucune-sonde-ne-correspond' ($motifs -join ', '))
        Write-Info (Get-Label 'check-probes.sondes-disponibles' (($probes | ForEach-Object { $_.Name -replace '\.probe\.ps1$','' }) -join ', '))
        exit 1
    }
    $probes = $retenues
}

# --- Passe -------------------------------------------------------------------
$executees = 0; $surEnregistrement = 0; $modules = 0
$reportLines = @()

foreach ($f in $probes) {
    $stamp     = Get-CodeStamp -File $f
    $ancien    = $record[$f.Name]
    $inchangee = ($ancien -and "$($ancien.codeStamp)" -eq $stamp)
    $couteuse  = ($ancien -and [int]$ancien.ms -ge $HeavyMs)

    # A probe that was explicitly asked for, or modified, or never recorded, is RUN.
    $doitExecuter = $All -or $Only -or -not $inchangee -or -not $couteuse

    if ($doitExecuter) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $rendus = $null
        $job = $null
        <#
            A PROBE THAT DOES NOT HAND BACK CONTROL IS A SHORTFALL, NOT A WAIT.

            On 01/09 this check stayed stuck for TWENTY-FOUR MINUTES: the deployment probe questions the git clone,
            and an installation was running at the same moment. Without a limit, a checker becomes the problem
            itself -- one can no longer tell whether it is working or dead.

            So the probe runs in a separate process, with a ceiling. Beyond it, we say so and move on to the next
            one: the report stays complete, and the cause is named.
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
            $shortfalls += "{0} : la sonde LEVE une erreur -- {1}" -f $f.Name, $_.Exception.Message
            $reportLines += '  {0,-20} ECHEC a l execution' -f $f.Name
            continue
        }
        finally { if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } }
        $sw.Stop()
        if (-not $rendus) {
            Write-ProbeRun -Backend $backendRoot -Probe $f.Name -Ms $sw.ElapsedMilliseconds -Origin 'check' -Outcome 'empty'
            $shortfalls += "$($f.Name) : la sonde ne rend AUCUN module"
            $reportLines += '  {0,-20} ECHEC : aucun module' -f $f.Name
            continue
        }
        $contrat = ConvertTo-Contract -Modules $rendus
        Write-ProbeRun -Backend $backendRoot -Probe $f.Name -Ms $sw.ElapsedMilliseconds -Origin 'check' -Outcome 'ok' -Modules @($contrat).Count
        $shortfalls += Test-Contract -Modules $contrat -Source $f.Name
        $modules += @($contrat).Count
        $executees++
        $reportLines += '  {0,-20} execute   {1,6:N0} ms   {2} module(s)' -f $f.Name, $sw.ElapsedMilliseconds, @($contrat).Count

        $record[$f.Name] = [ordered]@{
            at        = [datetime]::UtcNow.ToString('o')
            codeStamp = $stamp
            ms        = [int]$sw.ElapsedMilliseconds
            modules   = $contrat
        }
    }
    else {
        $contrat = $ancien.modules
        $shortfalls += Test-Contract -Modules $contrat -Source "$($f.Name) (sur enregistrement)"
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
        $reportLines += '  {0,-20} inchangee, verifiee sur sa sortie {1} ({2:N0} ms economisees)' -f $f.Name, $age, [int]$ancien.ms
    }
}

try {
    ($record | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $recordFile -Encoding UTF8
} catch {
    Write-Info (Get-Label 'check-probes.note-enregistrement-des-contrats')
}

# --- A guard: THE VISIBLE LABELS CARRY THEIR ACCENTS --------------------------
#
# A project rule (disciplines.md), recalled on 27/08: the accents should never be missing, everything must be in
# UTF-8. The code's comments are written without accents -- that is accepted and without consequence -- but
# EVERYTHING that is displayed must be written in correct French. The card announced two such labels stripped of
# their accents.
#
# We check only the strings MEANT FOR THE SCREEN: the ones following -Value, -Label, -Help, -Guide, -BusyLabel, or
# a "message =". The rest (paths, identifiers, file names) is not concerned.
#
# The list is deliberately SHORT: only words which, in this application, are never written without an accent. A
# guard that cries wrongly ends up ignored.
# Words SET ASIDE after trying, because they are ALSO written without an accent in French: one that is also a
# verb form, one that is also an adjective, and one that is also a variable name here. We prefer to catch a little
# less and be believed.



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
    $rootDir = Join-Path $backendRoot $d
    if (-not (Test-Path -LiteralPath $rootDir)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $rootDir -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue)) {
        $lineNo = 0
        foreach ($l in (Get-Content -LiteralPath $f.FullName -Encoding UTF8)) {
            $lineNo++
            # A comment is not displayed: we leave it alone.
            if ($l -match '^\s*#') { continue }
            # THE DASH MUST BEGIN A PARAMETER. Without that boundary, "Get-Label" contains "-Label": the invariant
            # read the KEY of a label -- deliberately in ASCII -- and demanded accents on it.
            foreach ($m in [regex]::Matches($l, '(?:(?<![\w-])(?:-Value|-Label|-Help|-Guide|-BusyLabel)|message\s*=)\s*("[^"]*"|''[^'']*'')')) {
                # Interpolated VARIABLES are not text displayed as it stands: a property name inside $( ) is not
                # the French word it happens to contain. We take them out before judging.
                $text = [regex]::Replace($m.Groups[1].Value, '\$\([^)]*\)|\$[A-Za-z_][A-Za-z0-9_.]*', ' ')
                if ($text -match $motifAccents) {
                    $sansAccent += ("{0}:{1} -- « {2} »" -f $f.Name, $lineNo, $Matches[1])
                }
            }
        }
    }
}
foreach ($x in $sansAccent) {
    $shortfalls += "libelle visible sans accent -- $x"
}

# --- A guard: NO EXTERNAL CALL THAT CAN ASK FOR INPUT -------------------------
#
# An installation runs with nobody in front of it. An external tool that asks a question and waits on standard
# input freezes it INDEFINITELY, with no message: one believes it has crashed, or worse one does not believe it and
# waits.
#
# Observed on 29/08: "schtasks /change /RU <account>" without /RP asks for the account's password. The installation
# stayed stuck for 28 seconds -- the time it took for somebody to press Enter, which supplied an EMPTY password.
# The error that followed was swallowed by a "$null = $out".
#
# The list is deliberately SHORT and precise: we do not guess which tool asks questions, we add the ones that have
# already cost us an evening.

$interactifs = @()
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include '*.ps1','*.cmd' -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    # "var" holds THE SERVICE'S CLONE (D112): a whole copy of the repository, which we would judge twice -- and in
    # which we fix nothing, since it regenerates itself.
    if ($rel -like '.claude/*' -or $rel -like 'dist/*' -or $rel -like 'local/*' -or $rel -like '*/var/*') { continue }
    # THIS file QUOTES the patterns it hunts: judging oneself makes no sense, and a checker that denounces itself
    # teaches its reader to ignore it.
    if ($rel -like '.claude/*' -or $rel -like 'dist/*' -or $rel -like 'local/*' -or
        $rel -eq 'scripts/check-probes.ps1') { continue }
    $lineNo = 0
    foreach ($l in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $lineNo++
        if ($l -match '^\s*#') { continue }
        # schtasks changing the account it runs under WITHOUT supplying the password.
        if ($l -match 'schtasks' -and $l -match '/RU\b' -and $l -notmatch '/RP\b') {
            $interactifs += ("{0}:{1} -- schtasks /RU sans /RP : demande le mot de passe et attend" -f $rel, $lineNo)
        }
        # Read-Host in a script that runs WITH NOBODY IN FRONT OF IT.
        #
        # The exception, and its reason: install-dev.ps1 is a development tool, started by hand. Its graphical
        # question can fail (no interface available); the command-line fallback then addresses somebody who IS in
        # front of it. Forbidding it would amount to taking away its only fallback.
        $unattended = ($rel -like 'scripts/*' -or $rel -like 'apps/backend-pode/*') -and
                        $rel -ne 'scripts/dev/install-dev.ps1'
        if ($l -match '\bRead-Host\b' -and $unattended) {
            $interactifs += ("{0}:{1} -- Read-Host : rien ne repondra si personne n'est devant" -f $rel, $lineNo)
        }
    }
}
foreach ($x in $interactifs) { $shortfalls += "appel qui attend une saisie -- $x" }

# --- A guard: NO ACCENTED TEXT AS AN ARGUMENT TO ANOTHER PROCESS --------------
#
# An accented text passed as an argument to ANOTHER process crosses the command line, and so the code page of the
# moment: an accented word came back mangled (observed on 29/08 on the installation's closing window). No FILE
# encoding can do anything about it -- the damage is done BETWEEN the two processes.
#
# show-confirm.ps1 can read the labels itself: we pass it KEYS (-TitleKey, -SummaryKey, -DetailsKey), which are
# pure ASCII. Passing it -Title, -Summary or -Details spelled out means taking again the road that damages the
# accents.

$plainText = @()
$plainParams = @('Title', 'Summary', 'Details')
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($rel -like '.claude/*' -or $rel -like 'dist/*' -or $rel -like 'local/*' -or $rel -like '*/var/*') { continue }
    # The file that carries the mechanism, and this checker, necessarily quote those names.
    if ($rel -eq 'scripts/lib/show-confirm.ps1' -or $rel -eq 'scripts/check-probes.ps1') { continue }
    $body = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $body) { continue }
    if ($body -notmatch 'show-confirm') { continue }
    foreach ($name in $plainParams) {
        # "-Title" followed by anything other than "Key": that is the spelled-out form.
        # THE DASH MUST BEGIN A PARAMETER: "Write-Title" contains "-Title".
        # The name must END there: "-DetailsArg" is not "-Details".
        if ($body -match ('(?<![\w])-' + $name + '(?![\w])')) {
            $plainText += ("{0} -- « -{1} » en clair : passer « -{1}Key »" -f $rel, $name)
        }
    }
}
foreach ($x in $plainText) { $shortfalls += "texte accentue en argument -- $x" }

# --- A guard: NO CONTROL CHARACTER in the sources -----------------------------
#
# The most expensive trap of this project, met seven times in one day: a backslash disappears on writing and
# leaves a control character behind. A backslash followed by v becomes 0x0B, by the digit 7 becomes 0x07, by t a
# tab. The file stays valid, the parser says nothing, and a path suddenly designates nothing at all -- silently.
# Two cases lived through: an inventory of accounts that was always empty, and a diagnosis that answered that the
# account had never opened a session, whatever happened.
#
# We detect it here, where it costs a second, rather than in production where it costs an evening. Only the ESC
# escape (0x1B) is tolerated: it serves to filter the ANSI codes.

$sourceFolders = @('apps', 'scripts', 'config', 'docs')
$interdits = @()
foreach ($d in $sourceFolders) {
    $rootDir = Join-Path $repoRoot $d
    if (-not (Test-Path -LiteralPath $rootDir)) { continue }
    $files = Get-ChildItem -LiteralPath $rootDir -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @('.ps1', '.psd1', '.psm1', '.html', '.md', '.json', '.cmd') -and
                               $_.FullName -notmatch '\\var\\' -and $_.FullName -notmatch '\\dist\\' }
    foreach ($f in $files) {
        $text = $null
        try { $text = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop } catch { continue }
        if (-not $text) { continue }
        # 0x1B (ESC) excluded: deliberately. 0x09/0x0A/0x0D: tab and line endings.
        if ($text -match "[\u0000-\u0008\u000B\u000C\u000E-\u001A\u001C-\u001F]") {
            $lineNo = 0
            foreach ($l in ($text -split "`r?`n")) {
                $lineNo++
                if ($l -match "[\u0000-\u0008\u000B\u000C\u000E-\u001A\u001C-\u001F]") {
                    $interdits += ("{0}:{1}" -f $f.FullName.Substring($repoRoot.Length + 1), $lineNo)
                }
            }
        }
    }
}
foreach ($i in $interdits) {
    $shortfalls += "caractere de controle dans une source (antislash mange ?) -- $i"
}

# --- A guard: NOBODY COMPUTES A DATA PATH BY HAND -----------------------------
#
# The installed program lives in Program Files, and that folder is READ ONLY (D97): only the current account's
# data is written, inside its profile. A "var/..." path assembled by hand short-circuits that rule and writes
# beside the program.
#
# This is not a theoretical precaution: it is exactly what prevented Vigie from starting on a standard account.
# The client app computed "$PSScriptRoot/var/log", Windows refused to create the folder, and the script died on
# its second line -- with no log, since the log was precisely what it was trying to create.
#
# Get-VarPath and Get-VarRoot know where the data goes. Nobody else.
$horsRegle = @()
foreach ($d in @('apps', 'scripts')) {
    $rootDir = Join-Path $repoRoot $d
    if (-not (Test-Path -LiteralPath $rootDir)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $rootDir -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue)) {
        # common.ps1 IS the implementation of the rule: it is the only place where those paths are built.
        if ($f.Name -eq 'common.ps1') { continue }
        $i = 0
        foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            $i++
            if ($line -match '^\s*#') { continue }
            if (($line -match 'Join-Path') -and ($line -match 'var[/\\](log|run|cache|secrets|history)')) {
                $horsRegle += ("{0}:{1}" -f (Resolve-Path -LiteralPath $f.FullName -Relative), $i)
            }
        }
    }
}
foreach ($x in $horsRegle) {
    $shortfalls += "chemin de donnees calcule a la main (utiliser Get-VarPath) -- $x"
}

# --- A guard: "WHO RUNS" IS NOT "WHO ASKS" ------------------------------------
#
# $env:USERNAME returns the account that RUNS the process. As long as the server app ran under somebody's account,
# it happened to be right BY ACCIDENT. Since it runs as a service under its own account, every place that used it
# to mean "the person in front of the screen" designates the service: the Accounts card showed "YOU" on the
# service account and took it out of the list of technical accounts (observed on 29/08).
#
# Three functions, three meanings, and the choice becomes a conscious one:
#   Get-ProcessAccount   -- who runs (true for the client app and for the scripts)
#   Get-RequesterAccount -- who asks, or $null if nobody is identified
#   Get-ActionRequester  -- who asks, with a fallback, to SIGN the audit log

$rawUserVar = @()
foreach ($d in @('apps', 'scripts')) {
    $rootDir = Join-Path $repoRoot $d
    if (-not (Test-Path -LiteralPath $rootDir)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $rootDir -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue)) {
        # common.ps1 IS the implementation of the rule: Get-ProcessAccount lives there.
        if ($f.Name -eq 'common.ps1') { continue }
        $i = 0
        foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            $i++
            if ($line -match '^\s*#') { continue }
            # THE PATTERN IS WRITTEN IN PIECES, or this file would report itself -- like the mojibake patterns of
            # check-encoding.
            if ($line -match ('\$env:' + 'USER' + 'NAME')) {
                $rawUserVar += ("{0}:{1}" -f (Resolve-Path -LiteralPath $f.FullName -Relative), $i)
            }
        }
    }
}
foreach ($x in $rawUserVar) {
    $shortfalls += (('$env:' + 'USER' + 'NAME') +
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
foreach ($x in $handBuilt) { $shortfalls += $x }

# --- Guard rail: WHO LISTENS ON A PORT IS ASKED OF WINDOWS DIRECTLY -----------
#
# The WMI cmdlets enumerate every connection of the computer before filtering: with 10 775 open on 14/09, knowing who
# listened on 47600 took 26 seconds, and the update of Vigie went from 98 to 225 seconds. Get-PortListener and
# Get-UdpEndpointOwner (scripts/lib/tcp-ports.ps1) ask for listeners only, in under 2 ms. The slow cmdlets are refused
# everywhere; their names are assembled so that this file does not refuse itself.
# THE SAME FOR PERFORMANCE COUNTERS: Get-Counter took 6.3 s for the GPU engines on 18/09 and waits a second of its own
# for every rate; VigiePdh (scripts/lib/system-metrics.ps1) reads them in milliseconds, when the caller chooses.
$slowPortCmdlets = '\b(' + 'Get-Net' + 'TCPConnection|' + 'Get-Net' + 'UDPEndpoint)\b'
$slowCounterCmdlet = '\b' + 'Get-' + 'Counter\b'
foreach ($d in @('apps', 'scripts')) {
    $rootDir = Join-Path $repoRoot $d
    if (-not (Test-Path -LiteralPath $rootDir)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $rootDir -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue)) {
        if ($f.FullName -like ('*' + [IO.Path]::DirectorySeparatorChar + 'var' + [IO.Path]::DirectorySeparatorChar + '*')) { continue }
        # THE ONE DOOR. scripts/lib/tcp-ports.ps1 owns port reading: the cheap gauge AND, in Get-HeldEphemeralPorts,
        # the complete one that alone sees the BOUND sockets and alone costs 1,5 s. Forbidding the call there would
        # forbid the reading altogether; letting it pass anywhere else would lose the cost. One door, and it is named.
        if ($f.Name -eq 'tcp-ports.ps1') { continue }
        $i = 0
        $inBlockComment = $false
        foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            $i++
            if ($inBlockComment) { if ($line -match '#>') { $inBlockComment = $false }; continue }
            if ($line -match '<#' -and $line -notmatch '#>') { $inBlockComment = $true; continue }
            if ($line -match '^\s*#') { continue }
            if ($line -match $slowPortCmdlets) {
                $shortfalls += ("appel WMI lent pour un port ({0}) : Get-PortListener ou Get-UdpEndpointOwner -- {1}:{2}" -f $Matches[1], (Resolve-Path -LiteralPath $f.FullName -Relative), $i)
            }
            if ($line -match $slowCounterCmdlet) {
                $shortfalls += ("compteur de performance lu sans VigiePdh -- {0}:{1}" -f (Resolve-Path -LiteralPath $f.FullName -Relative), $i)
            }
        }
    }
}

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
    $shortfalls += ("commentaire apres une continuation : la commande est coupee -- " + $x)
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
    foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $i++
        if ($line -match '^\s*#') { continue }
        # The pattern is assembled, or this file would report itself.
        # EVERY piece in its own brackets: the comma binds tighter than the plus, and without them the four
        # patterns glued back into ONE, which matched nothing.
        foreach ($pattern in @(('HK' + 'CU:'), ('$env:' + 'LOCALAPPDATA'), ('$env:' + 'APPDATA'), ('$env:' + 'USERPROFILE'))) {
            if ($line -like ('*' + $pattern + '*')) {
                $ambientUser += ("{0}:{1} -- {2}" -f (Resolve-Path -LiteralPath $f.FullName -Relative), $i, $pattern)
            }
        }
    }
}
foreach ($x in $ambientUser) {
    $shortfalls += ("utilisateur ambiant cote serveur (lire ruche par ruche ou profil par profil) -- " + $x)
}

# --- A guard: A CARD THAT SPEAKS OF "YOU" DECLARES ITSELF PerAccount ----------
#
# The probes' rendering is cached in state-cache.json, which is SHARED. A card that writes "(you)", sorts on the
# current account or shows only the requester's data therefore leaves there the answer computed for ONE person,
# served afterwards to all the others. That is what happened to the accounts card.
#
# The declaration "PerAccount = $true" in module.psd1 gives the probe one cache entry per account. It cannot be
# guessed: we check that it is there as soon as the probe's code looks at the requester.


$personalCards = @()
$probesRoot = Join-Path $repoRoot 'apps/backend-pode/probes'
foreach ($f in (Get-ChildItem -LiteralPath $probesRoot -Recurse -File -Filter '*.probe.ps1' -ErrorAction SilentlyContinue)) {
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $text) { continue }
    # THE MARK IS THE SOURCE, NOT THE WORD. Looking for ".current" caught "$scan.current" -- the FOLDER being
    # analysed in the disc card, which has nothing personal about it. What makes a card personal is where its data
    # comes from: the list of accounts (which carries a "you") or the requester.
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
    $shortfalls += "carte personnelle sans « PerAccount = `$true » dans son module.psd1 -- $x"
}

# --- Verdict -----------------------------------------------------------------
$reportLines | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Info (Get-Label 'check-probes.sonde-executee-verifiee-sur' $executees $surEnregistrement $modules)
if ($surEnregistrement -gt 0) {
    Write-Detail (Get-Label 'check-probes.une-sonde-verifiee-sur')
    Write-Detail (Get-Label 'check-probes.passe-complete-avant-livraison')
}

if ($shortfalls.Count -eq 0) {
    Write-Ok (Get-Label 'check-probes.tous-les-invariants-sont')
    exit 0
}
Write-Fail (Get-Label 'check-probes.manquement' $shortfalls.Count)
$shortfalls | ForEach-Object { Write-Host "  - $_" }
exit 1
