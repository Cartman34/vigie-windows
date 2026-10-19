# @author Florent HAZARD <f.hazard@sowapps.com>
# @layer: subject
# @uses: config, paths
<#
    Intent: TWO ENVIRONMENTS ON ONE MACHINE: a development repository and a shared installation, running side by side. Which one is declared, which one a path belongs to, which one is actually running, and how it is labelled on screen.
    Usage: dot-sourced by common.ps1, never run on its own.
#>

function Get-DeclaredStage {
    param([string]$Backend = (Get-BackendRoot))
    <#
        THE STAGE, NOT "THE ENVIRONMENT".

        "Environment" did not say what was being spoken of: this setting, the server, or the whole computer? It is
        a STAGE in the deployment sense -- dev, prod, and room for a "staging" later.

        The old name is still READ: a config.local.psd1 already laid on a machine must not stop working because a
        better word was found.
    #>

    try {
        $cfg = Get-Config -Backend $Backend
        foreach ($k in @('Stage', 'Environment')) {
            $value = "$($cfg.$k)".Trim().ToLowerInvariant()
            if ($value -in @('dev', 'prod')) { return $value }
        }
    } catch { }
    return 'prod'      # defaut : une machine est en production tant qu'on n'a pas dit l'inverse
}

# Where the running code comes from: under Program Files it is the shared installation; anywhere else it is a
# working repository. We read the PATH, not an intention.
function Get-PathStage {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $root) { continue }
        if ("$Path".StartsWith("$root", [StringComparison]::OrdinalIgnoreCase)) { return 'prod' }
    }
    return 'dev'
}

function Get-RunningStage {
    param([string]$Backend = (Get-BackendRoot))
    Get-PathStage -Path $Backend
}

# The label displayed, in plain words: "Production" does not say where the code comes from.
<#
    THE ENVIRONMENT SAYS THE SOURCE, NOT THE LOCATION.

    The labels read "Developpement (depot)" / "Production (installation partagee)", as if the code ran in two
    places. It runs in only one: the shared installation, development included. What changes is WHAT IS DEPLOYED
    THERE -- a branch of the repository, or a published version.
#>

function Get-StageLabel {
    param([Parameter(Mandatory)][ValidateSet('dev', 'prod')][string]$Stage)
    # THE ENVIRONMENT DOES NOT SAY THE SOURCE. Both labels named it ("source: the repository", "source: published
    # versions"): that is a SEPARATE setting (UpdateSource), and a production machine can synchronise from a local
    # clone without ceasing to be one. Two axes, neither deduced from the other.
    # AN INITIAL CAPITAL: this is a VALUE displayed in a card, not a word in the middle of a sentence --
    # check-probes verifies it. Sentences have labels of their own.


    if ($Stage -eq 'dev') { return 'Développement' }
    return 'Production'
}

# --- Atelier: present locally? -----------------------------------------------
# The Atelier is a development tool started BY HAND: Vigie's interface shows a link to it ONLY if it really
# answers. The detection lives here (on the server) because the front end cannot probe another port cleanly, and
# the Atelier's port is defined in ITS OWN config only (D15) -- we read it, we do not copy it.
function Get-AtelierUrl {
    param([string]$Backend = (Get-BackendRoot))
    try {
        $cfgPath = Join-Path (Get-RepoRoot) 'apps/atelier/config/config.psd1'
        if (-not (Test-Path -LiteralPath $cfgPath)) { return $null }
        $acfg = Import-PowerShellDataFile -Path $cfgPath
        $port = [int]$acfg.Port
        if (-not $port) { return $null }
        $addr = (Get-Config -Backend $Backend).BindAddress
        if (-not $addr) { $addr = '127.0.0.1' }
        # A raw TCP connection, short timeout: on the local host a closed port answers immediately -- this test
        # does not slow /health down.
        $c = [System.Net.Sockets.TcpClient]::new()
        try {
            if (-not $c.ConnectAsync($addr, $port).Wait(250)) { return $null }
        } finally { $c.Dispose() }
        return ('http://{0}:{1}/apps/atelier/index.html' -f $addr, $port)
    } catch { return $null }
}
