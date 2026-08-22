<# Action open-windows-update : ouvre les Parametres Windows Update (installation manuelle).
   N'installe rien : respecte le principe "rien sans consentement". #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'ms-settings:windowsupdate'
    @{ message = "Fenetre Windows Update ouverte. Pour installer : deverrouillez (Mode MAJ), installez, puis re-verrouillez."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir Windows Update : $($_.Exception.Message)"; result = @{ ok = $false } }
}
