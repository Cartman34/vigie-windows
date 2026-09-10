# @author Florent HAZARD <f.hazard@sowapps.com>
<# TOOL: the tray icon's own balloon.

   THE LAST RANK IS ALWAYS AVAILABLE, and that is its whole purpose. Every tool above it
   may decline -- a missing runtime, a locked session, an API this Windows does not carry --
   and a notification is never lost because of it.

   What it cannot do is why the others exist: the big glyph is one of Windows' three, the
   text is cut after two lines, and no button can be attached. #>
param($Notification, $Context)

if (-not $Context.Icon) { return $false }
$glyph = switch ("$($Notification.State)") { 'error' { 'Error' } 'warn' { 'Warning' } default { 'Info' } }
$duration = [int]$Notification.Duration
if ($duration -le 0) { $duration = 6000 }
try {
    $Context.Icon.ShowBalloonTip($duration, "$($Notification.Subject)", "$($Notification.Body)",
                                 [System.Windows.Forms.ToolTipIcon]::$glyph)
    return $true
} catch {
    return $false
}
