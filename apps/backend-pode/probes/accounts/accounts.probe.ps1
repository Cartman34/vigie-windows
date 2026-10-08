# @author Florent HAZARD <f.hazard@sowapps.com>
<# Probe: the ACCOUNTS of this computer. READ ONLY.

   ONE LINE PER ACCOUNT, as the owner asked: the name on the left, and facing it what
   matters -- whether Vigie is on, and what kind of account it is.

   ALL the user accounts, and ONLY those. A user account is one whose PROFILE HAS ALREADY
   BEEN USED: that single fact is what separates a person from a tool's account, and it
   needs no setting. (The account's LastLogon lies: a sandbox showed "signed in today"
   without ever having opened a session.)

   The detail -- last session, weight of the data -- belongs to the accounts-details action: a card is read at a
   glance, it does not unfold to hand over its main
   information. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$accounts = @(Get-UserAccounts)

$fields = @()
foreach ($c in ($accounts | Sort-Object @{ Expression = { -not $_.current } }, name)) {
    $state = @()
    $state += $(if ($c.enabled) { 'Vigie activée' } else { 'Vigie inactive' })
    $state += $(if ($c.admin) { 'administrateur' } else { 'standard' })

    $aide = @()
    $aide += $(if ($c.enabled) { "Vigie démarre à l'ouverture de session de ce compte." }
               else { "Vigie ne démarre pas avec ce compte. Pour l'activer : Paramètres > Utilisateurs." })
    $aide += $(if ($c.admin) { 'Compte administrateur : les actions qui modifient le système lui sont permises.' }
               else { 'Compte standard : Vigie lui refuse les actions administrateur, comme le ferait Windows.' })
    if ($c.current) { $aide += "C'est le compte qui utilise Vigie en ce moment." }

    # ENABLED DOES NOT MEAN IT WORKS. A task can exist, be well formed, and never have run
    # once -- which is what happened to "Famille" on 28/08 while this card showed a placid
    # "Vigie activée". So the fault is said ON THE ACCOUNT'S OWN LINE, where it is looked for.
    $lineStatus = 'neutral'
    if ($c.enabled -and $c.taskAilment) {
        $lineStatus = 'warn'
        $state += 'ne démarre pas'
        $aide += "Sa tâche de démarrage existe mais " + $c.taskAilment + "."
        $aide += "Le bouton « Vérifier le démarrage de Vigie » l'examine et la remet d'aplomb quand c'est réparable."
    }

    <#
        THE COLOUR SAYS THE STATE OF THE ACCOUNT, NOT "NOTHING TO REPORT".

        Every line came out grey, so there was no seeing at a glance who has Vigie and who
        does not. An account that has it, with a healthy task, is GREEN; an account without
        it stays neutral -- that is not a fault, it is a choice.

        THE PER-ACCOUNT DETAIL LIVES ON THE LINE. One had to open the accounts-details action to
        learn when the account last opened a session, or whether its task had ever run.
        Those three facts fit in the line's detail, where they are looked for.
    #>
    if ($lineStatus -eq 'neutral' -and $c.enabled) { $lineStatus = 'ok' }

    $lineDetail = @()
    $lineDetail += $(if ($c.fullName -and $c.fullName -ne $c.name) { $c.fullName } else { 'Pas de nom complet déclaré' })
    $lineDetail += $(if ($c.lastUse) { 'Dernière session : ' + $c.lastUse } else { "Jamais ouvert de session" })
    if ($c.task) {
        $lineDetail += 'Tâche de démarrage : ' + $c.task
        if ($c.taskPending -eq (Get-VigieTaskNeverRunText)) { $lineDetail += 'Elle ne s''est pas encore lancée.' }
        elseif ($c.taskPending) { $lineDetail += 'Son dernier démarrage a échoué : ' + $c.taskPending }
    } elseif ($c.enabled) {
        $lineDetail += "Aucune tâche de démarrage posée pour ce compte."
    }

    # A line that reports a fault carries the button that fixes it (D66): an orange status
    # with no gesture available leaves the reader facing a problem and nothing else.
    $fields += New-Field -Key ('acc-' + ($c.name -replace '[^A-Za-z0-9]', '')) `
        -Label ($c.name + $(if ($c.current) { ' (vous)' } else { '' })) `
        -Value ($state -join ' - ') -Kind 'text' -Status $lineStatus `
        -FixAction $(if ($lineStatus -eq 'warn') { 'repair-tasks' } else { $null }) `
        -Help ($aide -join ' ') `
        -Guide ($lineDetail -join [Environment]::NewLine)
}

if (-not $accounts.Count) {
    $fields += New-Field -Key 'aucun' -Label 'Comptes' -Value 'Aucun compte utilisateur' -Kind 'text' -Status 'neutral' `
        -Help "Aucun compte de cet ordinateur n'a encore ouvert de session."
}

# --- Card 1: the ACCOUNTS ----------------------------------------------------
# SCOPE: the accounts OF THE COMPUTER. What each of them holds is not read here.
$accountsCard = New-ModuleObject -Id 'accounts' -Theme 'accounts' -Label 'Comptes' -Scope 'machine' `
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

@($accountsCard)
