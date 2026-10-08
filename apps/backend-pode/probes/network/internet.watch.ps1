# @author Florent HAZARD <f.hazard@sowapps.com>
<# A READING: does the Internet answer? It returns yes or no. Nothing else.

   Intent: be CHEAP, which is the condition: this file runs every minute, permanently, even with no session
   open. A ping to an address that always answers is enough -- we measure neither the latency nor the throughput
   here, the Network card does that when it is asked for.
   Usage: it is declared as a sentinel in the module's module.psd1. The value returned is COMPARABLE: it is its
   change that makes an event, and the event makes the Network card be recomputed. See
   doc/progress/targeting/surveillance.md.
#>
$ok = $false
try {
    # -Quiet: a boolean, not an object. 1 attempt, 1 second: we want to know whether it answers, not how long it
    # takes.
    $ok = [bool](Test-Connection -TargetName '1.1.1.1' -Count 1 -TimeoutSeconds 1 -Quiet -ErrorAction Stop)
} catch { $ok = $false }
if ($ok) { 'oui' } else { 'non' }
