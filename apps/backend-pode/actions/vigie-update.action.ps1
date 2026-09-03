# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: admin   -- redeploie hors du profil et relance l'application (D65)
# @libelle: Mettre a jour Vigie | confirm | fix   -- affiche quand un champ cite cette action (D66)
<# Action : met a jour Vigie, puis la relance.

   D'ou vient le code depend de la machine, et la recuperation tranche toute seule (D99) :
   s'il existe un DEPOT sur le poste -- meme quand l'app serveur tourne depuis Program
   Files, car l'installation sait d'ou elle vient -- c'est lui la source, et le tag est
   pose au passage. Sinon, la derniere version publiee sur GitHub.

   Ce bouton ne fait rien de particulier : il lance L'INSTALLATION, la meme que
   setup.cmd, decrite dans doc/progress/targeting/install-update.md. Recuperer avant
   d'arreter, controler, arreter, sauvegarder, poser, verifier, redemarrer -- c'est elle
   qui sait dans quel ordre, et il n'y a pas de second exemplaire de cette sequence.

   Le tout sous le VEILLEUR (D82) : le code de sortie est constate et rapporte, une
   mise a jour ratee devient une ligne rouge sur la carte au lieu d'un silence. Le code
   3 -- deja a jour -- n'est PAS un echec (D77). #>
param([string]$Module, [hashtable]$Params)

$backend = Split-Path $PSScriptRoot -Parent
. (Join-Path $backend 'lib/common.ps1')

<#
    LE BOUTON APPELLE L'INSTALLATION, PAS UN AUTRE GESTE.

    Il lancait « vigie-update », qui faisait presque la meme chose que l'installation --
    mais pas tout a fait : deux chemins pour un seul geste, donc deux comportements a
    tenir et un qui derive. Depuis le 30/08 il n'y en a plus qu'un, decrit dans
    doc/progress/targeting/install-update.md.

    L'installation est lancee DETACHEE (le veilleur s'en charge) : elle arrete l'app
    serveur au milieu de sa sequence, or c'est l'app serveur qui l'a lancee. Un processus
    enfant mourrait avec elle et tout ce qui suit n'aurait jamais lieu.
#>
$script = Join-Path (Get-RepoRoot) 'scripts/install.ps1'
if (-not (Test-Path -LiteralPath $script)) {
    return @{ message = "Script d'installation introuvable : $script"; result = @{ ok = $false } }
}

$journal = Join-Path (Get-LogDir -Backend $backend) ('update_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
$pwsh = $null
try { $pwsh = (Get-Process -Id $PID).Path } catch { }
if (-not $pwsh) { $pwsh = 'pwsh.exe' }

$lance = $false
try {
    # RAW VALUES: Start-ChildProcess is what quotes them (D116).
    # QUI DEMANDE suit le script : il tourne detache, sous le compte du service, et c'est
    # dans la session du demandeur que le tag de version sera pose (D112).
    $argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
              '-File', $script)
    $demandeur = Get-RequesterAccount
    if ($demandeur) { $argv += @('-Requester', $demandeur) }
    # PAS DE FENETRE : le serveur n'a pas de bureau, elle n'irait nulle part.
    $argv += '-NoWindow'
    # ET ON LUI DIT QUE LA MARQUE « une operation tourne » EST LA SIENNE : le veilleur la
    # pose avant de la lancer, et l'installation refusait de tourner en la voyant.
    $argv += @('-FromAction', 'vigie-update')
    # La carte DEPLOIEMENT gere les deploiements -- et elle est toujours la. La carte de
    # debogage, elle, peut etre eteinte : le suivi de l'operation y aurait ete invisible.
    $lance = [bool](Start-WatchedAction -Module 'deployment' -Probe 'deployment.probe.ps1' `
                        -Label 'Mise à jour de Vigie' -Action 'vigie-update' `
                        -File $pwsh -Arguments $argv -Log $journal -Backend $backend)
    Write-Log -Backend $backend -Name 'update' -Message (Get-Label 'vigie-update.mise-jour-lancee-journal' $journal)
} catch {
    Write-Log -Backend $backend -Name 'update' -Level 'ERROR' -Message $_.Exception.Message
}

if (-not $lance) { return @{ message = "Impossible de lancer la mise à jour."; result = @{ ok = $false } } }

@{
    message = "Mise à jour lancée. Elle dure une trentaine de secondes, puis Vigie redémarre toute seule."
    result  = @{ ok = $true; async = $true; module = 'deployment'; invalidate = @('deployment.probe.ps1') }
}
