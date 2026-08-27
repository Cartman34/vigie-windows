<# Worker DETACHE unique : execute une operation paquet ('check' ou 'upgrade')
   pour UN gestionnaire, puis rafraichit le compte de MAJ et invalide la sonde.
   Lance par Start-PkgJob via Start-DetachedAction (pwsh cache). N'ecrit QUE dans
   var/cache + var/log. Traite erreurs + sortie via Get-PkgUpdates / Invoke-PkgUpgrade. #>
param([string]$Backend, [string]$ArgsB64)
if (-not $Backend) { return }
. (Join-Path $Backend 'lib/common.ps1')

# Parametres (JSON base64) : mgr + op + pkgs (paquets retenus, vide = tout).
$mgr = $null; $op = 'check'; $pkgs = @()
try {
    if ($ArgsB64) {
        $a = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64))) | ConvertFrom-Json
        $mgr = "$($a.mgr)"
        if ($a.op) { $op = "$($a.op)" }
        if ($a.pkgs) { $pkgs = @($a.pkgs | ForEach-Object { "$_" }) }
    }
} catch { }
if (-not $mgr) { return }

$outFile = Get-VarPath -Backend $Backend -Kind 'cache' -File 'pkgupdates.json'
try {
    if ($op -eq 'upgrade') {
        $up = Invoke-PkgUpgrade -Id $mgr -Pkgs $pkgs
        # On journalise ce qui a ETE FAIT (nombre de paquets, echecs constates), pas ce qui
        # a ete demande : un paquet peut echouer seul sans faire echouer les autres.
        $detail = if ($up.count) { " paquets=$($up.count)" } else { " (tout le gestionnaire)" }
        if ($up.failed -and @($up.failed).Count) { $detail += " echecs=" + (@($up.failed) -join ',') }
        try { Write-Log -Backend $Backend -Name 'pkgupgrade' -Message ("$mgr : exit=$($up.exit) ok=$($up.ok) reboot=$($up.reboot)$detail") } catch { }
        try {
            $logf = Join-Path (Get-LogDir -Backend $Backend) ("pkgupgrade_" + $mgr + "_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".log")
            "$($up.output)" | Out-File -FilePath $logf -Encoding UTF8
        } catch { }
    }
    # LAISSER LE GESTIONNAIRE REPRENDRE SON SOUFFLE.
    #
    # Le controle qui suit une mise a jour tournait dans la SECONDE : winget n'avait pas
    # encore rafraichi son inventaire et re-listait le paquet qu'il venait d'installer.
    # Vecu le 27/08 : Insomnia mis a jour avec succes (« Installe correctement », code 0)
    # et propose a nouveau deux secondes plus tard -- « j'ai demande a l'installer et en
    # retour, ce n'est pas installe ».
    if ($op -eq 'upgrade') { Start-Sleep -Seconds 12 }

    # Dans les deux cas on rafraichit le compte de MAJ (l'absence de "checking" = fin).
    $u = Get-PkgUpdates -Id $mgr

    # ET ON SAIT CE QU'ON VIENT DE FAIRE : un paquet dont la mise a jour a REUSSI ne se
    # repropose pas, meme si le gestionnaire l'annonce encore. Le journal fait foi --
    # code de sortie 0 et absent de la liste des echecs.
    if ($op -eq 'upgrade' -and $up -and @($pkgs).Count) {
        $reussis = @($pkgs | Where-Object { @($up.failed) -notcontains "$_" })
        if ($reussis.Count) {
            $restants = @(@($u.pkgs) | Where-Object { $reussis -notcontains "$($_.id)" })
            if (@($restants).Count -ne @($u.pkgs).Count) {
                $u = @{ count      = @($restants).Count
                        items      = @($restants | ForEach-Object { "$($_.titre)" })
                        pkgs       = @($restants)
                        supported  = $u.supported
                        selectable = $u.selectable }
                Write-Log -Backend $Backend -Name 'pkgupgrade' `
                          -Message ("$mgr : " + $reussis.Count + " paquet(s) retire(s) de la liste (mise a jour reussie)")
            }
        }
    }
    # `pkgs` (identifiants ciblables) est conserve avec le reste : la fenetre de choix le
    # relit tel quel, sans relancer une verification lente au moment du clic.
    $etat = @{ count = [int]$u.count; items = @($u.items); pkgs = @($u.pkgs); at = (Get-Date).ToString('s') }
    # Un redemarrage en attente doit se VOIR dans la carte : c'est une action attendue de
    # l'utilisateur, pas une ligne de journal.
    if ($op -eq 'upgrade' -and $up -and $up.reboot) { $etat.reboot = $true }
    # Le RESULTAT de la mise a jour est conserve pour la carte : sans lui, l'operation se
    # termine en silence et l'utilisateur ne sait pas ce qui a ete fait ni si ca a marche.
    if ($op -eq 'upgrade' -and $up) {
        $etat.last = @{
            at      = (Get-Date).ToString('s')
            ok      = [bool]$up.ok
            count   = if ($up.count) { [int]$up.count } else { 0 }   # 0 = tout le gestionnaire
            failed  = @($up.failed)
            reasons = $(if ($up.reasons) { $up.reasons } else { @{} })
        }
    }
    Update-StateJson -Path $outFile -Set @{ $mgr = $etat } | Out-Null
    Write-Log -Backend $Backend -Name 'pkgcheck' -Message ("$mgr ($op) : $([int]$u.count) MAJ disponible(s)")
} catch {
    try { Update-StateJson -Path $outFile -Set @{ $mgr = @{ count = 0; items = @(); at = (Get-Date).ToString('s'); error = $_.Exception.Message } } | Out-Null } catch { }
    Write-Log -Backend $Backend -Name 'pkgcheck' -Level 'ERROR' -Message ("$mgr ($op) : " + $_.Exception.Message)
}

# Rafraichissement immediat de la carte au prochain acces (sans attendre le TTL).
try { Remove-ProbeCache -Names @('packages.probe.ps1') -Backend $Backend } catch { }
