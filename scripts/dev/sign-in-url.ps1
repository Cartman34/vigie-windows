# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    SIGN-IN-URL: AN OPENING ADDRESS, TO PASTE INTO A REAL BROWSER.

    Intent: look at Vigie and debug it in one's usual browser -- developer tools, console, network -- rather than
    in the client app's window. Opening the panel's address by hand works, but the server does not know WHO is
    looking: nobody is "you" and no action knows who is asking for it.

    Usage: pwsh -File scripts/dev/sign-in-url.ps1 (-Open to open it straight away). Exit codes: 0 = an address
    was returned; 2 = a silent server, or an unreadable secret; 3 = a prod stage, where this script has no place.

    WHAT THIS SCRIPT RETURNS. A SINGLE-USE address, valid for 30 seconds. The server exchanges it for a session,
    then sends the browser back to the main address -- so the opening address stays neither in the address bar nor
    in a bookmark.

    THE SESSION, FOR ITS PART, DOES NOT EXPIRE. That is the intended sharing: what travels is disposable, what
    stays is not. One gets back in the saddle once, and the browser goes on being identified.

    FOR ONESELF, AND ONLY FOR ONESELF. The secret that proves the identity lives in the account's profile, with
    an explicit ACL. To open a session in another account's name, this script must be run INSIDE that session.

    DEV STAGE ONLY. Opening the panel in a separate browser is a development gesture: one looks at the console,
    the network, one refreshes fifty times. In a prod stage Vigie opens through its icon, and a second way of
    obtaining a session has no business there.

    That refusal states an INTENTION, it does not hold a boundary: what really protects the session is the
    account's secret, unreadable by the others. The stage is DECLARED (machine.psd1), never deduced.
#>




[CmdletBinding()]
param(
    # -Open: open it straight away in the default browser, instead of displaying it.
    [switch] $Open,
    [int] $Port = 0
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$backend  = Join-Path $repoRoot 'apps/backend-pode'
. (Join-Path $backend 'lib/common.ps1')

<#
    WE SAY WHERE WE STAND, AT EVERY STEP.

    The script said nothing until it had finished: when it did not hand control back, there was no way of knowing
    WHERE -- reading the secret, calling the server, or waiting for an answer that was not coming. A silent tool
    that runs for a long time is a tool one cannot debug.

#>
Write-Step (Get-Label 'sign-in-url.etape-stage')
$stage = Get-DeclaredStage -Backend $backend
if ("$stage" -ne 'dev') {
    Write-Fail (Get-Label 'sign-in-url.stage-prod' (Get-StageLabel -Stage $stage))
    Write-Detail (Get-Label 'sign-in-url.ouvrir-par-icone')
    exit 3
}

Write-Step (Get-Label 'sign-in-url.etape-serveur')
if (-not $Port) { $Port = [int](Get-Config -Backend $backend).Port }
if (-not (Get-PortListener -Port $Port)) {
    Write-Fail (Get-Label 'sign-in-url.personne-n-ecoute' $Port)
    exit 2
}

$account = Get-ProcessAccount
Write-Step (Get-Label 'sign-in-url.etape-adresse' $account)
# THE TIMEOUT IS SHORT AND IT IS STATED. The server answers in a few tenths of a second or it does not answer:
# waiting longer has never returned anything, except the impression that the tool is stuck.
$target = Get-OpenUrl -Account $account -BaseUrl ('http://127.0.0.1:' + $Port) -TimeoutSec 10 -Backend $backend
if (-not $target) {
    Write-Fail (Get-Label 'sign-in-url.adresse-refusee' $account)
    exit 2
}

Write-Ok (Get-Label 'sign-in-url.adresse-prete' $account)
Write-Detail (Get-Label 'sign-in-url.valable-une-fois')
Write-Host $target
if ($Open) { Start-Process $target }
exit 0
