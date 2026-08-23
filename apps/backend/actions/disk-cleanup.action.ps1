<# Action : ouvre l'outil de nettoyage de disque Windows. #>
param([string]$Module, [hashtable]$Params)
Start-Process cleanmgr.exe
@{ message = 'Outil de nettoyage de disque ouvert.'; result = @{ ok = $true } }
