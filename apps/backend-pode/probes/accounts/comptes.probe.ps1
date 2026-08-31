<# Sonde : les COMPTES de cet ordinateur. LECTURE SEULE.

   Une LIGNE PAR COMPTE (choix utilisateur) : le nom a gauche, et en face l'essentiel --
   Vigie active ou non, et le type de compte.

   TOUS les comptes utilisateurs, UNIQUEMENT eux (regle utilisateur). Un compte
   utilisateur est un compte dont le PROFIL A DEJA SERVI : c'est le seul fait qui
   distingue une personne d'un compte d'outil, et il ne demande aucun reglage.
   (Le LastLogon du compte, lui, ment : un bac a sable affichait « connecte
   aujourd'hui » sans avoir jamais ouvert de session.)

   Le detail (derniere session, poids des donnees) tient dans l'action « Details des
   comptes » : une carte se lit d'un coup d'oeil, elle ne se deplie pas pour livrer son
   information principale. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$eleve   = [bool](Test-IsElevated)
$comptes = @(Get-UserAccounts)

$fields = @()
foreach ($c in ($comptes | Sort-Object @{ Expression = { -not $_.current } }, name)) {
    $etat = @()
    $etat += $(if ($c.enabled) { 'Vigie activée' } else { 'Vigie inactive' })
    $etat += $(if ($c.admin) { 'administrateur' } else { 'standard' })

    $aide = @()
    $aide += $(if ($c.enabled) { "Vigie démarre à l'ouverture de session de ce compte." }
               else { "Vigie ne démarre pas avec ce compte. Pour l'activer : Paramètres > Utilisateurs." })
    $aide += $(if ($c.admin) { 'Compte administrateur : les actions qui modifient le système lui sont permises.' }
               else { 'Compte standard : Vigie lui refuse les actions administrateur, comme le ferait Windows.' })
    if ($c.current) { $aide += "C'est le compte avec lequel vous utilisez Vigie en ce moment." }

    # ACTIVEE NE VEUT PAS DIRE QUE CA MARCHE. Une tache peut exister, etre bien formee, et
    # n'avoir jamais demarre une seule fois -- c'est ce qui est arrive sur « Famille » le
    # 28/08, pendant que cette carte affichait un tranquille « Vigie activée ». Le defaut
    # se dit donc SUR LA LIGNE DU COMPTE, la ou on le cherche.
    $statutCompte = 'neutral'
    if ($c.enabled -and $c.taskAilment) {
        $statutCompte = 'warn'
        $etat += 'ne démarre pas'
        $aide += "Sa tâche de démarrage existe mais " + $c.taskAilment + "."
        $aide += "Le bouton « Vérifier le démarrage de Vigie » l'examine et la remet d'aplomb quand c'est réparable."
    }

    # Une ligne qui signale un defaut porte le bouton qui le corrige (D66) : un statut
    # orange sans geste possible laisse le lecteur devant un probleme et rien d'autre.
    $fields += New-Field -Key ('acc-' + ($c.name -replace '[^A-Za-z0-9]', '')) `
        -Label ($c.name + $(if ($c.current) { ' (vous)' } else { '' })) `
        -Value ($etat -join ' - ') -Kind 'text' -Status $statutCompte `
        -FixAction $(if ($statutCompte -eq 'warn') { 'repair-tasks' } else { $null }) `
        -Help ($aide -join ' ')
}

if (-not $comptes.Count) {
    $fields += New-Field -Key 'aucun' -Label 'Comptes' -Value 'Aucun compte utilisateur' -Kind 'text' -Status 'neutral' `
        -Help "Aucun compte de cet ordinateur n'a encore ouvert de session."
}

# --- Carte 1 : les COMPTES ---------------------------------------------------
$carteComptes = New-ModuleObject -Id 'accounts' -Theme 'accounts' -Label 'Comptes' `
    -Status $(if (@($fields | Where-Object { "$($_.status)" -eq 'error' }).Count) { 'error' }
              elseif (@($fields | Where-Object { "$($_.status)" -eq 'warn' }).Count) { 'warn' }
              else { 'ok' }) `
    -Fields $fields -Actions @(
        New-Action -Id 'accounts-details' -Label 'Détails des comptes' -Kind 'immediate' -Severity 'info' `
            -Help "Dernière ouverture de session et poids des données Vigie de chacun. Demande un compte administrateur."
        New-Action -Id 'accounts-refresh' -Label 'Actualiser la liste' -Kind 'immediate' -Severity 'neutral' `
            -BusyLabel 'Relevé…' `
            -Help "Refait le relevé des comptes. La liste est mémorisée 24 h : elle ne change qu'exceptionnellement."
        New-Action -Id 'open-users-settings' -Label 'Gérer les comptes' -Kind 'dialog' -Severity 'info' `
            -Help "Ouvre Paramètres > Utilisateurs : c'est là que l'on choisit les comptes avec lesquels Vigie démarre."
    )

<#
    CE QU'ON S'APPRETE A DEPLOYER, EN UNE PHRASE.

    La confirmation disait seulement « Deploie la version actuelle vers l'installation
    partagee ». Laquelle vers laquelle ? On peut cliquer sans savoir si l'on avance de
    deux commits ou si l'on ecrase une version plus recente.

    LE COMMIT N'EST MONTRE QU'EN DEVELOPPEMENT. En production, deux versions se
    distinguent par leur numero -- c'est a cela qu'il sert. En developpement, le numero
    ne bouge pas entre deux commits : sans lui, « v0.1.21 vers v0.1.21 » ne dit rien.
#>
$court = { param($c) if ($c) { $c.Substring(0, [Math]::Min(8, $c.Length)) } else { '' } }
$estDev = ((Get-DeclaredStage -Backend $backend) -eq 'dev')
$deVersion = ''; $versVersion = ''; $deNote = ''; $versNote = ''
if ($cmp) {
    $deVersion   = "$($cmp.there.version)"
    $versVersion = "$($cmp.here.version)"
    # Le commit N'APPARAIT QU'EN DEVELOPPEMENT : en production deux versions se
    # distinguent par leur numero, c'est a cela qu'il sert. En developpement il ne bouge
    # pas entre deux commits, et « v0.1.25 vers v0.1.25 » ne dirait rien.
    if ($estDev) {
        $deNote   = & $court $cmp.there.commit
        $versNote = & $court $cmp.here.commit
    }
} else {
    $deVersion   = 'rien'
    $versVersion = 'première installation'
}

@($carteComptes)
