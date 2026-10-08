# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    console-ui.ps1 -- THE SAME DISPLAY EVERYWHERE. No dependency: loadable by any script, under Windows
    PowerShell 5.1 as well as under PowerShell 7.

    Intent: make what a script says on screen mean the same thing whichever script says it, and make a verdict
    impossible to fake -- the colour is deduced from what happened, never asserted by the caller.
    Usage: dot-source it first (it also brings the labels, see below), then use the vocabulary and nothing else.

    WHY THIS FILE EXISTS. Every script had invented its own layout: arrows here, dashes there, nothing elsewhere;
    green meant "done" in one and "under way" in another. On 28/08 a step of the installation FAILED and the final
    line still said it was finished, in green -- the user had no way of seeing it. An inconsistent display is not a
    defect of style: it is false information.

    THE VOCABULARY, and nothing else:

      Write-Title    "Installation"        a block begins        (cyan, underlined)
      Write-Step     "PowerShell 7"        a step begins         (white, prefixed ::)
                                             and the previous one concludes, in colour
      Write-Ok       "installed"           a fact, successful    (grey, no marker)
      Write-Warn     "without the rights"  it passes, degraded   (yellow,  [!] )
      Write-Fail     "Windows refused"     it failed             (red,     [X] )
      Write-Info     "version 7.4.6"       a fact, no verdict    (grey)
      Write-Detail   "path: C:/..."        a secondary fact      (dark grey, indented)
      Write-Outcome  -Failures 0           the final verdict     (see further down)

    THE COLOUR RULE, invariable: green comes ONLY out of a success, red ONLY out of a failure. No script can end
    in green with a failure behind it, because Write-Outcome counts the failures instead of taking its word for
    it.

    THE ENCODING. This file is UTF-8 WITH a BOM: without it, Windows PowerShell 5.1 reads the accents as latin-1
    and displays them mangled. The markers stay pure ASCII ([ok], [X]): they cross every console, including those
    of a workstation where the code page has never been changed.
#>

<#
    WHAT WE WRITE COMES OUT IN UTF-8, EVEN REDIRECTED INTO A FILE.

    A script started by the watcher has its output redirected into a log. What Windows writes there follows
    [Console]::OutputEncoding, which is the system's code page (1252 here): so the accents went out as latin-1,
    and the card displayed a sentence full of question marks (observed on 31/08). The log was not readable back
    either.

    It is laid down HERE because everything displayed in this repository goes through this file: one single line,
    and no script has to think about it again.
#>

try {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Text.UTF8Encoding]::new($false)
} catch { }

# The failure counter of the running script. Write-Fail increments it; Write-Outcome reads it. That counter is what
# prevents an indulgent final verdict.
# THE LABELS COME WITH THE DISPLAY. These two files are neighbours: loading one gives the other, and no script has
# to think about it. It is this file's only dependency, and it does not leave its folder.
$_i18nPath = Join-Path $PSScriptRoot 'i18n.ps1'
if (Test-Path -LiteralPath $_i18nPath) { . $_i18nPath }

$script:UiFailures = 0
$script:UiWarnings = 0

function Write-Title {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host ""
    Write-Host $Text -ForegroundColor Cyan
    Write-Host (New-Object string ([char]0x2500), ([Math]::Min($Text.Length, 78))) -ForegroundColor DarkCyan
}

<#
    EVERY STEP SAYS HOW IT ENDS.

    A step used to open, run its lines, and the next one began: to know whether it had got there, one had to read
    its lines one by one and decide for oneself. The conclusion existed only at the very end, for the whole
    script.

    From now on every step closes with a LAST COLOURED LINE stating its fate. It is not written by the caller: it
    is DEDUCED from what happened between its opening and its closing -- red if there was a failure, yellow if
    there was a reservation, green otherwise. So a script cannot conclude a step in green when it failed, any more
    than it could for the final verdict.

    A step closes by itself: when the next one opens, or when the verdict falls.
#>

$script:UiStepText = $null
$script:UiStepFailures = 0
$script:UiStepWarnings = 0
# A failure or a reservation coming from a SUB-PROCESS: they colour the step's conclusion without touching the
# script's counters, which belong to its own observations.
$script:UiStepRelayFail = $false
$script:UiStepRelayWarn = $false

function Close-UiStep {
    if ($null -eq $script:UiStepText) { return }
    $f = $script:UiFailures - $script:UiStepFailures
    $w = $script:UiWarnings - $script:UiStepWarnings
    if ($script:UiStepRelayFail) { $f++ }
    if ($script:UiStepRelayWarn) { $w++ }
    $Text = if ($f -gt 0)    { $script:UiStepText + " : échec." }
             elseif ($w -gt 0) { $script:UiStepText + " : fait, avec " + $w + " réserve(s)." }
             else              { $script:UiStepText + " : fait." }
    $couleur = if ($f -gt 0) { 'Red' } elseif ($w -gt 0) { 'Yellow' } else { 'Green' }
    Write-Host ("       " + $Text) -ForegroundColor $couleur
    $script:UiStepText = $null
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Text)
    Close-UiStep
    Write-Host ""
    Write-Host (":: " + $Text) -ForegroundColor White
    $script:UiStepText = $Text
    $script:UiStepFailures = $script:UiFailures
    $script:UiStepWarnings = $script:UiWarnings
    $script:UiStepRelayFail = $false
    $script:UiStepRelayWarn = $false
}

<#
    AN INTERMEDIATE SUCCESS IS NOT A CONCLUSION.

    Green was laid on every success, and the reader no longer knew where to look: "there are green ok's and not
    all of them, one cannot really tell" (29/08). The "[ok]" marker went the same way: it decorated facts without
    ever saying where the step stood.

    There is no marker any more. An intermediate success is a grey line like the other facts; what concludes is
    the step's last line, in colour, and the final verdict. Red and yellow keep theirs -- a failure must leap to
    the eye wherever it is, and "[X]" is what the server reads back to say WHY an operation failed.
#>


function Write-Ok      { param([Parameter(Mandatory)][string]$Text) Write-Host ("       " + $Text) -ForegroundColor Gray }
function Write-Info    { param([Parameter(Mandatory)][string]$Text) Write-Host ("       " + $Text) -ForegroundColor Gray }
function Write-Detail  { param([Parameter(Mandatory)][string]$Text) Write-Host ("       " + $Text) -ForegroundColor DarkGray }

<#
    RELAYING A SUB-PROCESS'S OUTPUT WITHOUT MAKING IT LOSE ITS COLOUR.

    A script called as a child process writes its markers -- [X], [!] -- but its output comes back as TEXT: the
    caller re-displayed it as it stood, in white. So three build failures scrolled past in white in the middle of
    the rest (observed on 01/09), while those are exactly the lines one looks for.

    We read the marker again and give the colour back. The counters, for their part, DO NOT MOVE: those failures
    belong to the child, and the caller decides for itself what to make of them.
#>

function Write-Relayed {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $couleur = if ($Text -match '\[X\]') { 'Red' }
               elseif ($Text -match '\[!\]') { 'Yellow' }
               else { 'Gray' }
    # A RELAYED FAILURE MARKS THE STEP. The global counters do not move -- the caller will read the child's exit
    # code and decide -- but concluding "done" in green underneath three red lines is a lie: saying a deployment is
    # possible when there are plenty of errors is very optimistic.
    if ($Text -match '\[X\]')      { $script:UiStepRelayFail = $true }
    elseif ($Text -match '\[!\]') { $script:UiStepRelayWarn = $true }
    Write-Host $Text -ForegroundColor $couleur
}

function Write-Warn {
    param([Parameter(Mandatory)][string]$Text)
    $script:UiWarnings++
    Write-Host ("  [!]  " + $Text) -ForegroundColor Yellow
}

function Write-Fail {
    param([Parameter(Mandatory)][string]$Text)
    $script:UiFailures++
    Write-Host ("  [X]  " + $Text) -ForegroundColor Red
}

# How many failures and how many reservations has this script displayed? It serves to decide an exit code, and to
# title the closing window, without keeping a second counter by hand -- the one we forget to update.
#
# Get-UiWarningCount had been DELETED as dead code, then used again an hour later by the installation: "the term
# is not recognised", at the very end of the road, after everything else had succeeded. Deleting a public function
# is not free.



function Get-UiFailureCount { return $script:UiFailures }
function Get-UiWarningCount { return $script:UiWarnings }

<#
    THE FINAL VERDICT. We do not ask it to say that all is well, we give it the facts and it concludes. -Failures
    and -Warnings are optional: without them it counts what Write-Fail and Write-Warn displayed.

    Three outcomes, and only one is green:
      0 failures, 0 reservations  -> green   "Finished."
      0 failures, n reservations  -> yellow  "Finished, with n reservation(s)."
      n failures                  -> red     "FAILURE: n step(s) did not get there."
#>
function Write-Outcome {
    param(
        [string]$What = 'Terminé',
        [Nullable[int]]$Failures = $null,
        [Nullable[int]]$Warnings = $null,
        # What we advise doing next. One line, never a paragraph.
        [string]$NextStep = ''
    )
    # THE STEP UNDER WAY CLOSES BEFORE THE VERDICT: otherwise the last of all would never have said how it ended.
    Close-UiStep
    $f = if ($null -ne $Failures) { $Failures } else { $script:UiFailures }
    $w = if ($null -ne $Warnings) { $Warnings } else { $script:UiWarnings }

    # A BOX, NOT ONE MORE LINE. After thirty lines scrolling past, a conclusion must be seen without being looked
    # for -- it is the only thing one reads back when one returns to the screen.
    $text = if ($f -gt 0)    { "ÉCHEC : " + $f + " étape(s) n'ont pas abouti." }
             elseif ($w -gt 0) { $What + ", avec " + $w + " réserve(s)." }
             else              { $What + "." }
    $color = if ($f -gt 0) { 'Red' } elseif ($w -gt 0) { 'Yellow' } else { 'Green' }

    $width = $text.Length
    if ($NextStep -and $NextStep.Length -gt $width) { $width = $NextStep.Length }
    if ($width -gt 76) { $width = 76 }
    $rule = New-Object string ([char]0x2500), ($width + 2)

    Write-Host ""
    Write-Host ([char]0x250C + $rule + [char]0x2510) -ForegroundColor $color
    Write-Host ([char]0x2502 + ' ' + $text.PadRight($width) + ' ' + [char]0x2502) -ForegroundColor $color
    if ($NextStep) {
        Write-Host ([char]0x2502 + ' ' + $NextStep.PadRight($width) + ' ' + [char]0x2502) -ForegroundColor DarkGray
    }
    Write-Host ([char]0x2514 + $rule + [char]0x2518) -ForegroundColor $color
    Write-Host ""
}
