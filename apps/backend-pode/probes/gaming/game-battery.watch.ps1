# @author Florent HAZARD <f.hazard@sowapps.com>
<# RELEVE : la partie en cours vide-t-elle la batterie ?

   BON MARCHE, c'est la condition : ce fichier tourne en permanence, meme sans session
   ouverte. Il ne cherche PAS le jeu -- le retrouver coute deux instantanes de tous les
   processus. Il lit la session ouverte par la sonde Jeux (var/run/game-session.json),
   verifie que le processus vit encore, et compare la charge d'aujourd'hui a celle du
   debut de la partie.

   La valeur rendue est COMPARABLE, et elle change PAR PALIERS : « baisse-10 », puis
   « baisse-15 »... Chaque palier franchi est un changement, donc un evenement, donc un
   recalcul de la carte Jeux -- et c'est la bascule du champ « Alimentation » qui fait
   partir la bulle Windows (D54). Sans paliers, une decharge continue n'aurait fait
   qu'un seul evenement au tout debut.

   Voir doc/progress/targeting/surveillance.md.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$session = Get-GameSession -Backend $backend
if (-not $session) { 'non'; return }

# Secteur branche, ou machine sans batterie : rien a signaler.
$battery = Get-BatteryState
if (-not $battery.OnBattery -or $null -eq $battery.Pct) { 'non'; return }

$drop = [int]$session.startPct - [int]$battery.Pct
$seuil = [int](Get-ModuleSetting -Unit 'gaming' -Key 'BatteryDropWarnPct'); if (-not $seuil) { $seuil = 10 }
if ($drop -lt $seuil) { 'non'; return }

# Palier de 5 points : on alerte a nouveau quand la decharge se creuse, pas a chaque releve.
'baisse-' + ([math]::Floor($drop / 5) * 5)
