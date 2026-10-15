# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    EVERY VERIFIER OF THE REPOSITORY, IN ONE COMMAND. READ ONLY.

    Why it exists. Before each delivery the verifiers of scripts/dev are run one by one, and the list grows: on 13/09
    it held ten, plus the probes check. A list typed from memory loses one; this script finds them by their name,
    check-*.ps1, so a new verifier is run the day it is added.

    AND IT RUNS WHAT THE CHANGE CALLS FOR. Sixteen verifiers cost forty seconds; paid on a one-line change to a
    document, that cost buys nothing and teaches the habit of skipping the validation. So the ordinary pass reads
    WHAT CHANGED and wakes the verifiers that change concerns. Running everything is an OPTION one asks for, never
    the automatic road. The target is written in doc/en/agent-working/disciplines.md, section "The validation runs
    what the change calls for".

    Usage:
      pwsh -File scripts/dev/check-all.ps1                      # the ordinary road: what is not committed
      pwsh -File scripts/dev/check-all.ps1 -All                 # everything, whatever changed -- a DELIVERY
      pwsh -File scripts/dev/check-all.ps1 -Files a.ps1,b.html  # these files, and what they drag in
      pwsh -File scripts/dev/check-all.ps1 -FilesFrom list.txt  # the same, one path per line, for a long list
      pwsh -File scripts/dev/check-all.ps1 -Uncommitted         # the list asked of git
      pwsh -File scripts/dev/check-all.ps1 -Probes              # adds scripts/check-probes.ps1 -All, which EXECUTES

    What it shows. One line per verifier, and the full output of those that fail, so a green run stays short.
    Exit codes: 0 = every verifier agrees; 2 = at least one failed.
#>
[CmdletBinding()]
param(
    # Adds scripts/check-probes.ps1 -All, which executes every probe: slower, and required before a delivery that
    # touches a probe (doc/en/agent-working/briefing.md).
    [switch] $Probes,
    # Every verifier, whatever changed. What a delivery uses.
    [switch] $All,
    # These files -- and what they drag in through @related.
    [string[]] $Files,
    # The same, read from a file, one path per line: a list can outgrow a command line, and a temporary file is
    # the clean way through, not a workaround.
    [string] $FilesFrom,
    # The list asked of git rather than received. Same treatment afterwards.
    [switch] $Uncommitted
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

<#
    WHAT WAKES EACH VERIFIER: A FOLDER, AND A PATTERN WHEN IT MUST BE NARROWED.

    A folder says WHERE the subject lives; a bare extension says only what it is made of. The table lives here, in
    the orchestrator, because it is the orchestrator's decision -- and the sixteen lines are read at a glance.
    What is NOT here: the link between two files that must be validated together. That one is a relation between
    them, declared on the files themselves with `@related:` (server.ps1 and api/openapi.yaml name each other).

    The patterns are not guessed: they are what each verifier actually walks, read in its own code on 15/10.
    A verifier absent from this table is woken by ANY change -- the default checks more, never less.
#>
$WAKES = [ordered]@{
    'check-author'      = @(@{ Folder = ''; Patterns = @('*') })                       # l'en-tete de tout fichier
    'check-coherence'   = @(@{ Folder = ''; Patterns = @('*.ps1', '*.psd1', '*.html', '*.md') })
    'check-components'  = @(@{ Folder = 'apps/'; Patterns = @('*.ps1') },
                            @{ Folder = 'doc/progress/implemented/'; Patterns = @('components.md') })
    'check-local'       = @(@{ Folder = ''; Patterns = @('*.ps1') })      # les regles locales a un fichier
    'check-contract'    = @(@{ Folder = 'apps/backend-pode/'; Patterns = @('server.ps1', 'openapi.yaml') })
    'check-decisions'   = @(@{ Folder = 'doc/progress/'; Patterns = @('decisions.md') })
    'check-doc'         = @(@{ Folder = 'doc/'; Patterns = @('*.md') })
    'check-encoding'    = @(@{ Folder = ''; Patterns = @('*') })                       # accents, BOM, caracteres de controle
    'check-front'       = @(@{ Folder = 'apps/frontend-web/'; Patterns = @('*.html') })
    'check-labels'      = @(@{ Folder = ''; Patterns = @('*.ps1', '*.html', '*.json') })
    'check-language'    = @(@{ Folder = 'doc/'; Patterns = @('*.md') })
    'check-naming'      = @(@{ Folder = ''; Patterns = @('*.ps1', '*.psm1', '*.psd1', '*.html', '*.php', '*.py',
                                                         '*.json', '*.yaml', '*.cmd', '*.vbs', '*.md') })
    'check-operations'  = @(@{ Folder = ''; Patterns = @('*.ps1', '*.md') })
    'check-powershell'  = @(@{ Folder = ''; Patterns = @('*.ps1', '*.psd1') })
    'check-reachable'   = @(@{ Folder = ''; Patterns = @('*') })                       # qui appelle quoi, partout
    'check-scope'       = @(@{ Folder = 'apps/backend-pode/'; Patterns = @('*.ps1') })
    'check-sets'        = @(@{ Folder = ''; Patterns = @('*.ps1') })
}

# What a changed probe calls for, and what this script does NOT run on its own: executing the probes costs a
# minute of machine, so it is asked for (-Probes) and merely SUGGESTED here.
$PROBE_PATTERNS = @('*.probe.ps1', '*.watch.ps1', 'module.psd1')

<#
    1. THE LIST. Received (-Files), read from a file (-FilesFrom), or asked of git -- the three roads end in the
    same treatment. With nothing asked, the ordinary road: what is not committed, and failing that the files of
    the last commit, so a validation run right after committing still has something to say.
#>
function Get-SubjectFiles {
    param([Parameter(Mandatory)][string]$Root, [string[]]$Given, [string]$FromFile, [switch]$FromGit)
    $found = @()
    if ($Given) { $found += $Given }
    if ($FromFile) {
        if (-not (Test-Path -LiteralPath $FromFile -PathType Leaf)) {
            throw (Get-Label 'check-all.liste-introuvable' $FromFile)
        }
        $found += @(Get-Content -LiteralPath $FromFile -Encoding UTF8 | Where-Object { "$_".Trim() })
    }
    if (-not $found.Count -or $FromGit) {
        foreach ($line in @(& git -C $Root status --short 2>$null)) {
            if (-not "$line".Trim()) { continue }
            $path = "$line".Substring(2).Trim().Trim('"')
            # A rename is written "old -> new": what counts is where the file is now.
            if ($path -match ' -> ') { $path = ($path -split ' -> ')[-1].Trim().Trim('"') }
            if ($path) { $found += $path }
        }
        if (-not $found.Count -and -not $FromGit) {
            $found += @(& git -C $Root diff-tree --no-commit-id --name-only -r HEAD 2>$null |
                        Where-Object { "$_".Trim() })
        }
    }
    return @($found | ForEach-Object { "$_".Trim().Replace([char]92, [char]47) } | Where-Object { $_ } | Sort-Object -Unique)
}

<#
    2. WHAT THE LIST DRAGS IN. A file declares what it is bound to with `@related: <path>`, and a pair that must
    form whichever side moves declares it on BOTH sides. Only the headers of the CHANGED files are read -- which
    is why the link is written twice when it must work both ways.
#>
function Expand-RelatedFiles {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Paths)
    $linked = @()
    foreach ($rel in $Paths) {
        $full = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        foreach ($line in (Get-Content -LiteralPath $full -TotalCount 40 -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            $m = [regex]::Match("$line", '@related\s*:\s*([^-]+)')
            if (-not $m.Success) { continue }
            foreach ($piece in ($m.Groups[1].Value -split '[,;]')) {
                $piece = "$piece".Trim()
                if ($piece) { $linked += $piece.Replace([char]92, [char]47) }
            }
        }
    }
    return @(@($Paths + $linked) | Sort-Object -Unique)
}

# 3. THE SELECTION. A verifier is woken when one of the files falls in one of its folders AND matches one of its
#    patterns. No entry in the table: it is woken by anything.
<#
    WHO RECEIVES THE LIST. A verifier that declares a `-Files` parameter is asked about those files and nothing
    else -- check-local does. The others are run whole: they read what they have always read, and the selection
    only decided whether to wake them.

    It is READ from the verifier, not held in a table here: the day one of them learns to take a list, it says so
    itself and the orchestrator follows without being told.
#>
function Test-AcceptsFiles {
    param([Parameter(Mandatory)][string]$Path)
    $errors = $null; $tokens = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if (-not $tree -or ($errors -and $errors.Count)) { return $false }
    $block = $tree.ParamBlock
    if (-not $block) { return $false }
    foreach ($parameter in $block.Parameters) {
        if ($parameter.Name.VariablePath.UserPath -eq 'Files') { return $true }
    }
    return $false
}

function Test-Woken {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Paths)
    if (-not $WAKES.Contains($Name)) { return $true }
    foreach ($entry in $WAKES[$Name]) {
        foreach ($path in $Paths) {
            if ($entry.Folder -and -not $path.StartsWith($entry.Folder, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $leaf = Split-Path $path -Leaf
            foreach ($pattern in $entry.Patterns) {
                if ($leaf -like $pattern -or $path -like $pattern) { return $true }
            }
        }
    }
    return $false
}

$pwsh = (Get-Process -Id $PID).Path
$runs = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'check-*.ps1' -File |
          Where-Object { $_.Name -ne 'check-all.ps1' } | Sort-Object Name |
          ForEach-Object { [pscustomobject]@{ Name = $_.BaseName; Path = $_.FullName; Arguments = @() } })

$subject = @()
$asleep = @()
$temporaries = @()
if (-not $All) {
    $subject = Expand-RelatedFiles -Root $repoRoot -Paths (Get-SubjectFiles -Root $repoRoot -Given $Files -FromFile $FilesFrom -FromGit:$Uncommitted)
    if ($subject.Count) {
        $awake = @()
        foreach ($run in $runs) {
            if (-not (Test-Woken -Name $run.Name -Paths $subject)) { $asleep += $run.Name; continue }
            # THE LIST GOES THROUGH A FILE, always: a command line has a ceiling, and a list of changed files has
            # none. One road, whatever its length -- no special case to discover the day it is long.
            if (Test-AcceptsFiles -Path $run.Path) {
                $listFile = Join-Path ([IO.Path]::GetTempPath()) ('vigie-' + $run.Name + '-' + [guid]::NewGuid().ToString('N') + '.txt')
                Set-Content -LiteralPath $listFile -Value $subject -Encoding UTF8
                $run.Arguments = @('-FilesFrom', $listFile)
                $temporaries += $listFile
            }
            $awake += $run
        }
        $runs = $awake
    }
}

if ($Probes) {
    $runs += [pscustomobject]@{ Name = 'check-probes'; Path = (Join-Path (Join-Path $repoRoot 'scripts') 'check-probes.ps1'); Arguments = @('-All') }
}

Write-Title (Get-Label 'check-all.titre')
if ($All) {
    Write-Info (Get-Label 'check-all.tout' $runs.Count)
} elseif ($subject.Count) {
    Write-Info (Get-Label 'check-all.selection' $subject.Count $runs.Count)
    if ($asleep.Count) { Write-Detail (Get-Label 'check-all.au-repos' ($asleep -join ', ')) }
    if (-not $Probes) {
        $touchedProbe = @($subject | Where-Object { $p = Split-Path $_ -Leaf; @($PROBE_PATTERNS | Where-Object { $p -like $_ }).Count })
        if ($touchedProbe.Count) { Write-Warn (Get-Label 'check-all.sonde-touchee') }
    }
} else {
    Write-Info (Get-Label 'check-all.rien-de-change' $runs.Count)
}

$failed = @()
foreach ($run in $runs) {
    $started = Get-Date
    $output = @(& $pwsh -NoProfile -File $run.Path @($run.Arguments) 2>&1)
    $code = $LASTEXITCODE
    $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    if ($code -eq 0) {
        Write-Ok (Get-Label 'check-all.accord' $run.Name $seconds)
    } else {
        Write-Fail (Get-Label 'check-all.echec' $run.Name $code $seconds)
        foreach ($line in $output) { if ("$line".Trim()) { Write-Detail "$line" } }
        $failed += $run.Name
    }
}

foreach ($t in $temporaries) { Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue }

if ($failed.Count) { Write-Warn (Get-Label 'check-all.echecs' ($failed -join ', ')) }
Write-Outcome -What (Get-Label 'check-all.termine') -Failures $failed.Count
if ($failed.Count) { exit 2 }
exit 0
