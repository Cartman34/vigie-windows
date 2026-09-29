# @author Florent HAZARD <f.hazard@sowapps.com>
<#
    MODE: is the machine quiet right now?

    Some computations are worth their cost only when nobody is using the machine for anything better. Listing the
    packages questions winget, choco and pip and takes 3,7 s; it is wanted once a day, at a quiet moment -- the
    owner's words on 29/09 -- and never while the processor is already busy.

    Cheap by construction: one 250 ms sample of the total processor load, and the games mode read from what the watch
    has already recorded. Nothing is started, nothing is enumerated.
#>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

# A game is never a quiet moment, whatever the processor says.
if (Get-GameModeName -Backend $backend) { 'non'; return }

$load = Get-ProcessorLoad -SampleMs 250
if ($null -eq $load) { 'inconnu'; return }
if ($load -le 25) { 'oui'; return }
'non'
