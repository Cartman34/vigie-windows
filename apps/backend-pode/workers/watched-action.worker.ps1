# @author Florent HAZARD <f.hazard@sowapps.com>
<# Worker : lance un programme, ATTEND sa fin, et rapporte son sort.

   Pourquoi il existe (D82). Une action longue etait lancee « detachee » et oubliee :
   personne ne lisait son code de sortie. Le 26/08, le bouton « Installer PowerShell 7 »
   a echoue en 0x80070005 -- l'interface n'a rien affiche, aucune notification n'est
   sortie, et la panne n'a ete comprise qu'en ouvrant un journal a la main. Pire : cet
   echec avait desinstalle le PowerShell existant.

   Ce veilleur tient le marqueur « occupe » de la carte pendant le travail, puis ecrit
   le RESULTAT (code de sortie, duree, journal) la ou la sonde saura le lire. Un echec
   devient donc une ligne rouge sur la carte et une notification, comme n'importe quel
   autre constat. #>
param(
    [Parameter(Mandatory)][string]$Backend,
    [Parameter(Mandatory)][string]$ArgsB64
)
$ErrorActionPreference = 'Stop'
. (Join-Path $Backend 'lib/common.ps1')

$a = $null
try {
    $a = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64)) | ConvertFrom-Json
} catch { }
if (-not $a -or -not $a.module -or -not $a.file) { return }

$module = "$($a.module)"
$label  = "$($a.label)"
$action = "$($a.action)"
$argv   = @($a.arguments)
$log    = "$($a.log)"

$t0 = Get-Date
# Le marqueur porte NOTRE pid : tant que ce veilleur vit, le travail est en cours.
# Il vit exactement aussi longtemps que l'enfant, puisqu'il l'attend.
$ressources = @($a.resources)
Set-ModuleBusyMark -Module $module -Label $label -ProcessId $PID -Action $action `
                   -Resources $ressources -Backend $Backend

$code = -1
$erreur = ''
try {
    $params = @{ FilePath = "$($a.file)"; Wait = $true; PassThru = $true; WindowStyle = 'Hidden' }
    if ($argv.Count) { $params['ArgumentList'] = $argv }
    if ($log) {
        $params['RedirectStandardOutput'] = $log
        $params['RedirectStandardError']  = ($log -replace '\.log$', '.err.log')
    }
    $p = Start-Process @params
    $code = [int]$p.ExitCode
} catch {
    $erreur = "$($_.Exception.Message)"
}

$duree = [int]((Get-Date) - $t0).TotalSeconds
Set-ModuleLastRun -Module $module -Action $action -Label $label -Code $code -Seconds $duree `
                  -Log $log -Error $erreur -Backend $Backend
Clear-ModuleBusyMark -Module $module -Backend $Backend

$niveau = if ($code -eq 0) { 'INFO' } else { 'ERROR' }
Write-Log -Backend $Backend -Name 'actions' -Level $niveau `
          -Message (Get-Label 'watched-action.code-en' $label $code $duree $(if ($erreur) { " -- " + $erreur }))
# Les valeurs de la carte ont change : qu'elle se recalcule au prochain affichage.
try { Remove-ProbeCache -Names @("$($a.probe)") -Backend $Backend } catch { }
