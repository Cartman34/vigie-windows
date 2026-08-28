<#
    check-reachable.ps1 - AUCUN FICHIER QUE PLUS RIEN N'APPELLE. LECTURE SEULE.

    POURQUOI CE FICHIER EXISTE. `scripts/lib/account-secret.ps1` a vécu une journée entière
    sans être chargé nulle part : écrit avant son consommateur, il ne faisait rien, et
    AUCUN vérificateur ne pouvait le voir — ni la syntaxe, ni les libellés, ni l'encodage,
    ni les sondes. Du code invisible qui donne l'illusion d'une fonctionnalité livrée.

    LE PIÈGE À ÉVITER, ET C'EST LUI QUI DICTE TOUT LE RESTE. Un fichier peut être
    parfaitement vivant sans qu'aucune ligne de code ne le nomme :

      - un script que l'humain lance à la main (`pwsh -File scripts\vigie-update.ps1`) ;
      - un script lancé par une tâche planifiée, un `.cmd`, ou une action ;
      - une sonde ou une action chargée PAR CONVENTION, par balayage du dossier ;
      - un outil de développement, appelé depuis la documentation ou par habitude.

    Un contrôle qui crierait sur ceux-là serait ignoré en trois jours — c'est exactement ce
    qui est arrivé au cliquet des noms français quand il annonçait 604 pour un plafond de
    302. On préfère donc RATER quelques fichiers morts plutôt que d'en accuser un vivant.

    CE QUI COMPTE COMME « ATTEIGNABLE », dans l'ordre :
      1. il est nommé dans un fichier du dépôt : code, `.cmd`, documentation, JSON ;
      2. il vit dans un dossier chargé par convention (sondes, actions, travailleurs) ;
      3. c'est un point d'entrée déclaré ci-dessous, avec sa raison.

    Usage :
      pwsh -File .\scripts\dev\check-reachable.ps1
      pwsh -File .\scripts\dev\check-reachable.ps1 -Detail

    Codes de retour : 0 = tout est atteignable ; 2 = au moins un fichier orphelin.
#>
param(
    [switch] $Detail
)
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot 'scripts/lib/console-ui.ps1')

$SKIPPED = @('.claude', '.git', 'dist', 'node_modules', 'local', 'var')

# Les dossiers dont TOUT le contenu est charge par convention : le serveur les balaie,
# personne ne nomme leurs fichiers un par un.
$BY_CONVENTION = @(
    'apps/backend-pode/actions',
    'apps/backend-pode/probes',
    'apps/backend-pode/workers'
)

<#
    LES POINTS D'ENTREE, chacun avec sa raison d'etre.

    Cette liste est le coeur du vérificateur : elle dit ce qu'on lance sans qu'aucun code
    ne le nomme. Elle doit rester COURTE et JUSTIFIEE — une liste qui enfle est une liste
    qui ne veut plus rien dire. Ajouter une ligne ici, c'est affirmer « ce fichier est
    lance par un humain ou par Windows », et la raison doit le montrer.
#>
$ENTRY_POINTS = [ordered]@{
    'scripts/install.ps1'            = 'lance par setup.cmd, et par l''utilisateur'
    'scripts/run.ps1'                = 'lance par run.cmd'
    'scripts/tray.ps1'               = 'outil en ligne de commande : etat, arret, relance'
    'apps/backend-pode/start.ps1'    = 'lance par le tray et par la tache serveur'
    'apps/tray/tray.ps1'             = 'lance par la tache de demarrage de chaque compte'
    'apps/atelier/atelier.ps1'       = 'atelier de validation, lance a la main'
}

# --- Qui nomme qui ----------------------------------------------------------------------
$files = @()
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in '.ps1', '.psm1' })) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($SKIPPED | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    $files += $rel
}

# Le texte de TOUT le depot, pas seulement des .ps1 : un .cmd, une doc ou un JSON qui
# nomme un script le rend atteignable. C'est precisement le cas qu'un controle naif rate.
$corpus = New-Object System.Text.StringBuilder
foreach ($f in (Get-ChildItem -LiteralPath $repoRoot -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1', '.cmd', '.bat', '.md', '.json', '.html', '.js', '.py' })) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart([char]92, [char]47).Replace([char]92, [char]47)
    if ($SKIPPED | Where-Object { $rel -like ($_ + '/*') -or $rel -like ('*/' + $_ + '/*') }) { continue }
    try { [void]$corpus.AppendLine("### $rel"); [void]$corpus.AppendLine([IO.File]::ReadAllText($f.FullName)) } catch { }
}
$texte = $corpus.ToString()

$orphelins = @()
foreach ($rel in $files) {
    if ($ENTRY_POINTS.Contains($rel)) { continue }
    if ($BY_CONVENTION | Where-Object { $rel -like ($_ + '/*') }) { continue }

    $nom = Split-Path $rel -Leaf
    # On cherche le NOM DU FICHIER, pas son chemin : il est ecrit tantot avec des barres
    # obliques, tantot avec des antislashs, tantot par Join-Path morceau par morceau.
    # Le nom seul est le seul denominateur commun.
    $motif = [regex]::Escape($nom)
    $occurrences = ([regex]::Matches($texte, $motif)).Count
    # Une occurrence est la sienne : la ligne « ### <chemin> » qu'on a posee en tete.
    if ($occurrences -le 1) { $orphelins += $rel }
}

# --- Verdict ----------------------------------------------------------------------------
Write-Title 'Fichiers atteignables'
Write-Info ("{0} script(s) examine(s), {1} point(s) d'entree declare(s)" -f $files.Count, $ENTRY_POINTS.Count)

if ($Detail) {
    Write-Step "Points d'entrée déclarés"
    foreach ($e in $ENTRY_POINTS.GetEnumerator()) { Write-Detail ("{0,-32} {1}" -f $e.Key, $e.Value) }
}

if ($orphelins.Count) {
    Write-Fail ("{0} fichier(s) que rien ne nomme :" -f $orphelins.Count)
    foreach ($o in $orphelins) { Write-Detail $o }
    Write-Info "Soit il est mort et se supprime, soit il est lancé autrement et se déclare ci-dessus."
    Write-Outcome -Failures 1
    exit 2
}
Write-Ok 'Tout script est nommé quelque part, ou déclaré comme point d''entrée.'
Write-Outcome -Failures 0
exit 0
