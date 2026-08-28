# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
<# Action open-windows-update : ouvre les Parametres Windows Update (installation manuelle).
   N'installe rien : respecte le principe "rien sans consentement". #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'ms-settings:windowsupdate'
    @{ message = "Fenêtre Windows Update ouverte. Pour installer : déverrouillez (Mode MAJ), installez, puis re-verrouillez."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir Windows Update : $($_.Exception.Message)"; result = @{ ok = $false } }
}
