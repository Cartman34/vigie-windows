# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- shows a notification in the requester's own session (D65)
# @execution: session   -- a notification belongs to a session: it must appear where somebody looks
# @libelle: Envoyer une notification d'essai | immediate | info   -- shown when a field names this action (D66)
<# Action: sends a real notification, by the same door as the others.

   Why it exists: memory saturation, exhausted ports, system errors, Vigie running away -- every alert added in
   September announces itself through a desktop notification, and not one of them has ever been seen on screen. A
   mechanism nobody has watched work is a promise, not a feature. This action sends one, through Show-VigieNotification
   and its tools, exactly like a real alert: what fails here would have failed for a real one.

   It says WHICH tool showed it (WinRT, balloon, fallback), because that is the part that varies between accounts and
   Windows versions, and the part a diagnosis needs. #>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$clientRoot = Join-Path (Split-Path $backend -Parent) 'client'
$icon = Join-Path $clientRoot 'vigie.ico'
$when = (Get-Date).ToString('HH:mm:ss')
$tool = $null
try {
    $tool = Show-VigieNotification `
        -Notification @{ Subject = 'Vigie — notification d''essai'
                         Body    = "Si vous lisez ceci, les alertes de Vigie savent atteindre cet écran ($when)."
                         State   = 'ok'; Duration = 6000; Key = 'vigie.essai' } `
        -Context @{ ClientRoot = $clientRoot; Aumid = (Get-VigieToastIdentity); Icon = $icon }
} catch {
    return @{ message = "L'essai a échoué : $($_.Exception.Message)"; result = @{ ok = $false } }
}
if ($tool) {
    @{ message = "Notification envoyée, affichée par « $tool ». Si rien n'apparaît à l'écran, le refus vient de Windows : Paramètres > Système > Notifications."
       result = @{ ok = $true; tool = $tool } }
} else {
    @{ message = "Aucun outil n'a su afficher la notification. Les alertes de Vigie n'atteignent donc pas cet écran : Paramètres > Système > Notifications, puis réessayer."
       result = @{ ok = $false } }
}
