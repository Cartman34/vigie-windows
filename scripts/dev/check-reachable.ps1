# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    check-reachable.ps1 -- NO FILE THAT NOTHING CALLS ANY MORE. READ ONLY.

    Intent: catch code that is invisible and gives the illusion of a delivered feature.
    `scripts/lib/account-secret.ps1` lived a whole day without being loaded anywhere: written before its
    consumer, it did nothing, and NO checker could see it -- neither the syntax, nor the labels, nor the
    encoding, nor the probes.

    Usage: pwsh -File .\scripts\dev\check-reachable.ps1 (-Detail to see each orphan). Exit codes: 0 =
    everything is reachable; 2 = at least one orphan file.

    THE TRAP TO AVOID, AND IT IS WHAT DICTATES ALL THE REST. A file can be perfectly alive without a single line
    of code naming it:

      - a script a human starts by hand (`pwsh -File scripts/vigie-update.ps1`);
      - a script started by a scheduled task, a `.cmd`, or an action;
      - a probe or an action loaded BY CONVENTION, by scanning the folder;
      - a development tool, called from the documentation or out of habit.

    A check that shouted about those would be ignored within three days -- which is exactly what happened to the
    French-name ratchet when it announced 604 against a ceiling of 302. So we prefer to MISS a few dead files
    rather than accuse a live one.

    WHAT COUNTS AS "REACHABLE", in order:
      1. it is named in a file of the repository: code, a `.cmd`, documentation, JSON;
      2. it lives in a folder loaded by convention (probes, actions, workers);
      3. it is an entry point declared below, with its reason.
#>

#>
param(
    [switch] $Detail
)
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$SKIPPED = @('.claude', '.git', 'dist', 'node_modules', 'local', 'var')

# The folders whose WHOLE content is loaded by convention: the server scans them, nobody names their files one by
# one.
$BY_CONVENTION = @(
    'apps/backend-pode/actions',
    'apps/backend-pode/probes',
    'apps/backend-pode/workers'
)

<#
    THE ENTRY POINTS, each with its reason for being.

    This list is the heart of the checker: it says what is started without any code naming it. It must stay
    SHORT and JUSTIFIED -- a list that swells is a list that no longer means anything. Adding a line here means
    asserting that this file is started by a human or by Windows, and the reason must show it.
#>
$ENTRY_POINTS = [ordered]@{
    'scripts/install.ps1'            = 'lance par setup.cmd, et par l''utilisateur'
    'scripts/run.ps1'                = 'lance par run.cmd'
    'scripts/client.ps1'               = 'outil en ligne de commande : etat, arret, relance'
    'apps/backend-pode/start.ps1'    = 'lance par l''app cliente et par la tache serveur'
    'apps/client/client.ps1'             = 'lance par la tache de demarrage de chaque compte'
    'apps/atelier/atelier.ps1'       = 'atelier de validation, lance a la main'
    'scripts/dev/decisions.ps1'      = 'consultation de la source de verite, lance a la main'
    'scripts/dev/sign-in-url.ps1'    = 'adresse d''ouverture pour un vrai navigateur, lance a la main'
}

# --- Who names whom -----------------------------------------------------------
$files = @()
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in '.ps1', '.psm1' })) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($SKIPPED | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    $files += $rel
}

# The text of the WHOLE repository, not only of the .ps1 files: a .cmd, a document or a JSON that names a script
# makes it reachable. That is precisely the case a naive check misses.
$corpus = New-Object System.Text.StringBuilder
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1', '.cmd', '.bat', '.md', '.json', '.html', '.js', '.py' })) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($SKIPPED | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    try { [void]$corpus.AppendLine("### $rel"); [void]$corpus.AppendLine([IO.File]::ReadAllText($f.FullName)) } catch { }
}
$Text = $corpus.ToString()

$orphelins = @()
foreach ($rel in $files) {
    if ($ENTRY_POINTS.Contains($rel)) { continue }
    if ($BY_CONVENTION | Where-Object { $rel -like ($_ + '/*') }) { continue }

    $name = Split-Path $rel -Leaf
    # We look for the FILE'S NAME, not its path: it is written sometimes with forward slashes, sometimes with
    # backslashes, sometimes through Join-Path piece by piece. The name alone is the only common denominator.
    $motif = [regex]::Escape($name)
    $occurrences = ([regex]::Matches($Text, $motif)).Count
    # One occurrence is its own: the header line we laid down at the top.
    if ($occurrences -le 1) { $orphelins += $rel }
}

<#
    THE FILES UNDER « assets/ »: SAME RULE, BUT WITH NO WAY OUT.

    A script can be alive without a single line naming it -- a human launches it, Windows launches it. An ASSET
    cannot: an image, a font, a data file are only of use if something designates them. There is therefore no entry
    point to declare here, and the control can be strict.

    On 07/10, apps/frontend-web/assets/ carried essai-info.png, specimen-vigie-icons.png and vigie-icons.b64, and
    apps/client/assets/ three .png nobody ever opened: six files, 60 KB, in every clone, for nothing. Two were
    images, which the owner had asked not to keep in the repository. Nothing could say so: this verifier read
    only the .ps1.
#>
$ASSET_EXT = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ico', '.webp', '.ttf', '.woff', '.woff2', '.b64', '.svg')
$assets = @()
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in $ASSET_EXT })) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($SKIPPED | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    if ($rel -notlike '*assets/*') { continue }
    $assets += $rel
}
$deadAssets = @()
foreach ($rel in $assets) {
    $leaf = Split-Path $rel -Leaf
    # The corpus carries one "### <path>" line per file read; that line is not a designation.
    # Assets are not in the corpus (they are binary), so any occurrence found is a real reference.
    if (([regex]::Matches($Text, [regex]::Escape($leaf))).Count -eq 0) { $deadAssets += $rel }
}

# --- Verdict ----------------------------------------------------------------------------
Write-Title 'Fichiers atteignables'
Write-Info ("{0} script(s) et {1} asset(s) examine(s), {2} point(s) d'entree declare(s)" -f $files.Count, $assets.Count, $ENTRY_POINTS.Count)

if ($Detail) {
    Write-Step "Points d'entrée déclarés"
    foreach ($e in $ENTRY_POINTS.GetEnumerator()) { Write-Detail ("{0,-32} {1}" -f $e.Key, $e.Value) }
}

if ($deadAssets.Count) {
    Write-Fail ("{0} fichier(s) d'assets que rien ne désigne :" -f $deadAssets.Count)
    foreach ($o in $deadAssets) { Write-Detail $o }
    Write-Info "Un asset que rien ne nomme ne sert à rien : il se supprime. Il n'y a pas de point d'entrée pour un asset."
    Write-Outcome -Failures 1
    exit 2
}
if ($orphelins.Count) {
    Write-Fail ("{0} fichier(s) que rien ne nomme :" -f $orphelins.Count)
    foreach ($o in $orphelins) { Write-Detail $o }
    Write-Info "Soit il est mort et se supprime, soit il est lancé autrement et se déclare ci-dessus."
    Write-Outcome -Failures 1
    exit 2
}
Write-Ok 'Tout script est nommé quelque part ou déclaré comme point d''entrée, et tout asset est désigné.'
Write-Outcome -Failures 0
exit 0
