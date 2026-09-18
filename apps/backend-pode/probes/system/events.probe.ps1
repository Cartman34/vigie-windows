# @author Florent HAZARD <f.hazard@sowapps.com>
<# Probe: the errors Windows wrote in its System log over the last 24 hours (SYS-EVENTS). READ ONLY, fast.

   EVERY POSSIBLE ERROR IS DETECTED, ABOVE ALL THE SYSTEM'S (answer of 18/09, notes/answers.md). On 17/09 the TCP and
   UDP ports ran out and the desktop heap failed, all of it written in this log, while the cards said nothing: the
   user saw only "server unreachable" and a glitching terminal.

   The kinds Vigie knows how to read are named with their meaning and their gesture; the others are listed by source,
   with their count and their last message, so that nothing Windows reports stays invisible.

   Measured on 18/09: levels 1 to 3 over 24 hours, 0.08 s for 43 events -- Get-WinEvent with a hashtable filter is
   evaluated by the log service itself, so the cost follows what is returned, not the size of the log. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

# THE KNOWN KINDS, by source and identifier -- an identifier alone is ambiguous: 153 is a disk timeout for 'disk' and a
# graphics driver error for 'nvlddmkm'. Each source and identifier was read on this computer before being named here.
$kinds = @(
    @{ Key = 'ports'; Status = 'error'; Label = 'Ports réseau épuisés'
       Match = @{ 'Tcpip' = @(4231, 4266) }
       Meaning = "Windows n'avait plus de port réseau libre : les connexions de toutes les applications échouaient, Vigie comprise."
       Gesture = "Le détail des ports occupés est sur la carte Réseau ; fermer ou redémarrer l'application qui en tient le plus les libère." }
    @{ Key = 'desktop-heap'; Status = 'error'; Label = 'Mémoire du Bureau épuisée'
       Match = @{ 'Win32k' = @(704) }
       Meaning = "Windows n'a pas pu réserver la mémoire d'une fenêtre : des fenêtres ne s'ouvrent plus ou s'affichent mal."
       Gesture = "Fermer les applications qui ouvrent beaucoup de fenêtres ou de consoles ; un redémarrage de Windows remet cette mémoire à zéro." }
    @{ Key = 'exhaustion'; Status = 'error'; Label = 'Mémoire virtuelle épuisée'
       Match = @{ 'Microsoft-Windows-Resource-Exhaustion-Detector' = @(2004) }
       Meaning = "La mémoire promise aux applications a atteint sa limite : Windows a refusé des allocations."
       Gesture = "La carte Ressources nomme les applications qui en occupent le plus ; fermer la plus lourde libère sa part." }
    @{ Key = 'bugcheck'; Status = 'error'; Label = 'Écran bleu'
       Match = @{ 'Microsoft-Windows-WER-SystemErrorReporting' = @(1001) }
       Meaning = "Windows s'est arrêté sur une erreur fatale et a redémarré."
       Gesture = "Le message donne le code d'arrêt ; il désigne le plus souvent un pilote ou un matériel." }
    # LevelDecides: a corrected hardware error is logged as a warning and changes nothing; only an error level alarms.
    @{ Key = 'hardware'; Status = 'error'; LevelDecides = $true; Label = 'Erreur matérielle'
       Match = @{ 'Microsoft-Windows-WHEA-Logger' = @() }
       Meaning = "Le processeur, la mémoire ou un bus a signalé une erreur matérielle."
       Gesture = "Une erreur isolée corrigée est sans suite ; répétée, elle annonce une panne : le message nomme le composant." }
    @{ Key = 'disk'; Status = 'error'; Label = 'Erreur de disque'
       Match = @{ 'disk' = @(7, 11, 51, 153); 'Ntfs' = @(55, 98, 137); 'storahci' = @(129); 'stornvme' = @(129); 'iaStorAC' = @(129); 'iaStorA' = @(129) }
       Meaning = "Un disque n'a pas répondu, a renvoyé une erreur de lecture ou d'écriture, ou son système de fichiers est abîmé."
       Gesture = "Sauvegarder ce qui compte ; l'état de santé du disque se vérifie avec l'outil de son fabricant, le système de fichiers avec « chkdsk »." }
    @{ Key = 'shutdown'; Status = 'warn'; Label = 'Arrêt inattendu'
       Match = @{ 'Microsoft-Windows-Kernel-Power' = @(41); 'EventLog' = @(6008) }
       Meaning = "Windows a redémarré sans s'être arrêté proprement : blocage, coupure de courant ou bouton maintenu."
       Gesture = "Une coupure isolée est sans suite ; répétée, elle désigne l'alimentation, la température ou un pilote." }
    @{ Key = 'graphics'; Status = 'warn'; Label = 'Pilote graphique en erreur'
       Match = @{ 'Display' = @(4101); 'nvlddmkm' = @(); 'amdkmdag' = @(); 'igfx' = @() }
       Meaning = "Le pilote de la carte graphique a signalé une erreur ; elle s'accompagne souvent d'un écran noir ou figé un instant, ou d'un jeu fermé."
       Gesture = "Mettre à jour le pilote graphique ; si l'erreur revient en jeu, la température de la carte graphique est à surveiller." }
    @{ Key = 'service-crash'; Status = 'warn'; Label = "Service arrêté brutalement"
       Match = @{ 'Service Control Manager' = @(7031, 7034) }
       Meaning = "Un service Windows s'est terminé de manière inattendue ; Windows l'a relancé s'il est réglé pour le faire."
       Gesture = "Le message nomme le service ; s'il revient souvent, sa propre carte ou son éditeur dit pourquoi." }
)
function Get-EventKind {
    param($Event)
    foreach ($k in $kinds) {
        if (-not $k.Match.ContainsKey($Event.ProviderName)) { continue }
        $ids = @($k.Match[$Event.ProviderName])
        if ($ids.Count -eq 0 -or $ids -contains $Event.Id) { return $k }
    }
    return $null
}
function Format-EventMessage {
    param($Event)
    $text = ''
    try { $text = "$($Event.Message)" } catch { }
    # A driver whose message file is missing gives no text: the identifier is then all there is to show.
    if (-not $text.Trim()) { return "(aucun texte fourni par la source, identifiant $($Event.Id))" }
    $text = ($text -replace '\s+', ' ').Trim()
    if ($text.Length -gt 180) { $text = $text.Substring(0, 179) + '…' }
    return $text
}
function Format-EventTime {
    param([datetime]$When)
    if ($When.Date -eq (Get-Date).Date) { return $When.ToString('HH:mm') }
    if ($When.Date -eq (Get-Date).Date.AddDays(-1)) { return 'hier ' + $When.ToString('HH:mm') }
    return $When.ToString('dd/MM HH:mm')
}

$events = @()
$readError = $null
try {
    $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2, 3; StartTime = (Get-Date).AddHours(-24) } -ErrorAction Stop)
} catch {
    # "No events were found" is the quiet case, not a failure.
    if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { $readError = $_.Exception.Message }
}

$known = @{}
$others = @{}
foreach ($e in $events) {
    $kind = Get-EventKind $e
    if ($kind) {
        if (-not $known.ContainsKey($kind.Key)) { $known[$kind.Key] = @{ Kind = $kind; Count = 0; Last = $e; Status = 'warn' } }
        $known[$kind.Key].Count++
        if (-not $kind.LevelDecides -or $e.Level -le 2) { $known[$kind.Key].Status = $kind.Status }
        if ($e.TimeCreated -gt $known[$kind.Key].Last.TimeCreated) { $known[$kind.Key].Last = $e }
    } elseif ($e.Level -le 2) {
        # A warning of an unknown kind is left out: the log holds hundreds of harmless ones a month (DCOM, the
        # processor throttled by its firmware), and listing them would bury the errors.
        $name = "$($e.ProviderName)"
        if (-not $others.ContainsKey($name)) { $others[$name] = @{ Count = 0; Last = $e } }
        $others[$name].Count++
        if ($e.TimeCreated -gt $others[$name].Last.TimeCreated) { $others[$name].Last = $e }
    }
}

# KNOWN ERRORS: named, with their meaning and their gesture.
$knownList = @($known.Values | Sort-Object { $_.Last.TimeCreated } -Descending)
$knownStatus = 'ok'
if (@($knownList | Where-Object { $_.Status -eq 'error' }).Count) { $knownStatus = 'error' }
elseif ($knownList.Count) { $knownStatus = 'warn' }
$knownValue = if ($knownList.Count) { (@($knownList | ForEach-Object { $_.Kind.Label }) -join ', ') } else { 'Aucune' }
$knownTable = $null
$knownGuide = $null
$knownReason = $null
if ($knownList.Count) {
    $knownTable = @{ columns = @('Dernière', 'Erreur', 'Fois', 'Dernier message')
                     rows = @(foreach ($k in $knownList) { ,@((Format-EventTime $k.Last.TimeCreated), $k.Kind.Label, "$($k.Count)", (Format-EventMessage $k.Last)) }) }
    $knownGuide = (@(foreach ($k in $knownList) {
        $k.Kind.Label + ' (' + $k.Count + ' fois, la dernière ' + (Format-EventTime $k.Last.TimeCreated) + ') : ' + $k.Kind.Meaning + ' ' + $k.Kind.Gesture
    }) -join ([Environment]::NewLine + [Environment]::NewLine))
    $knownReason = (@($knownList | Select-Object -First 3 | ForEach-Object { $_.Kind.Label + ' (' + (Format-EventTime $_.Last.TimeCreated) + ')' }) -join ', ')
}

# OTHER ERRORS: listed by source, so that nothing the log says stays invisible.
$otherList = @($others.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending)
$otherCount = [int](($otherList | ForEach-Object { $_.Value.Count } | Measure-Object -Sum).Sum)
$otherTable = $null
if ($otherList.Count) {
    $otherTable = @{ columns = @('Source', 'Fois', 'Dernière', 'Dernier message')
                     rows = @(foreach ($o in $otherList) { ,@($o.Key, "$($o.Value.Count)", (Format-EventTime $o.Value.Last.TimeCreated), (Format-EventMessage $o.Value.Last)) }) }
}

$fields = @(
    New-Field -Key 'known' -Label 'Erreurs système' -Value $knownValue -Kind 'text' -Status $knownStatus `
        -Table $knownTable -Guide $knownGuide -Reason $knownReason `
        -FixAction $(if ($knownList.Count) { 'open-event-viewer' } else { $null }) `
        -Help "Les erreurs graves que Windows a consignées dans son journal Système ces dernières 24 heures : ports réseau ou mémoire épuisés, arrêt inattendu, pilote graphique, disque, matériel, service arrêté brutalement."
    New-Field -Key 'others' -Label 'Autres erreurs' -Value $otherCount -Kind 'number' -Status 'neutral' -Table $otherTable `
        -FixAction $(if ($otherCount) { 'open-event-viewer' } else { $null }) `
        -Help "Les autres erreurs du journal Système ces dernières 24 heures, par source. Beaucoup sont sans conséquence ; une source qui revient souvent mérite un coup d'œil."
)
if ($readError) {
    $fields = @(New-Field -Key 'read' -Label 'Lecture du journal' -Value 'Impossible' -Kind 'text' -Status 'error' -Reason $readError `
        -Help "Le journal Système de Windows n'a pas pu être lu : $readError") + $fields
}
$worst = if ($readError -or $knownStatus -eq 'error') { 'error' } elseif ($knownStatus -eq 'warn') { 'warn' } else { 'ok' }
New-ModuleObject -Id 'events' -Theme 'system' -Label 'Journal Windows' -Status $worst -Fields $fields
