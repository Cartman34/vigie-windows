# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @libelle: Redémarrer Windows | confirm | fix   -- affiche quand un champ cite cette action (D66)
<# Action : redemarrer Windows.

   C'est le geste le plus intrusif de l'application : il ferme tout ce que l'utilisateur a
   ouvert. Trois precautions, dans cet ordre :

   1. l'interface demande DEUX confirmations distinctes (contrat : confirmTwice) ;
   2. le redemarrage est DIFFERE de 60 secondes, pas immediat ;
   3. il reste ANNULABLE pendant ce delai (action system-restart-cancel).

   Un redemarrage immediat et irrevocable derriere un seul clic serait un piege.
#>
param([string]$Module, [hashtable]$Params)
$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

$delai = 60
if ($Params -and $Params.delay) {
    try { $d = [int]$Params.delay; if ($d -ge 0 -and $d -le 3600) { $delai = $d } } catch { }
}

# shutdown.exe plutot que Restart-Computer : lui seul sait DIFFERER et se laisser annuler.
$r = Invoke-Native -File 'shutdown.exe' -Arguments @(
    '/r', '/t', "$delai", '/c', "Redemarrage demande depuis Vigie. Enregistrez votre travail."
)
if (-not $r.Ok) {
    return @{
        message = "Le redémarrage n'a pas pu être programmé (code $($r.ExitCode)). $($r.Output)"
        result  = @{ ok = $false }
    }
}

Update-StateJson -Path (Get-VarPath -Backend $backend -Kind 'cache' -File 'restart.json') -Set @{
    pending = $true
    at      = (Get-Date).ToUniversalTime().ToString('o')
    delay   = $delai
} | Out-Null

@{
    message = "Redémarrage programmé dans $delai secondes. Vous pouvez encore l'annuler."
    result  = @{ ok = $true; invalidate = @('lock.probe.ps1','pending.probe.ps1') }
}
