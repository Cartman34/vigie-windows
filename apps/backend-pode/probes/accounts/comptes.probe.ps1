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
$comptes = @(Get-VigieAccounts | Where-Object { -not $_.technical })

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

    $fields += New-Field -Key ('acc-' + ($c.name -replace '[^A-Za-z0-9]', '')) `
        -Label ($c.name + $(if ($c.current) { ' (vous)' } else { '' })) `
        -Value ($etat -join ' - ') -Kind 'text' -Status $statutCompte `
        -Help ($aide -join ' ')
}

if (-not $comptes.Count) {
    $fields += New-Field -Key 'aucun' -Label 'Comptes' -Value 'Aucun compte utilisateur' -Kind 'text' -Status 'neutral' `
        -Help "Aucun compte de cet ordinateur n'a encore ouvert de session."
}

# =============================================================================
# DEUXIEME CARTE : LE DEPLOIEMENT
#
# Cette sonde rendait UNE carte qui parlait de deux choses : qui a Vigie sur cette
# machine, et comment Vigie y est installee. L'utilisateur l'a vu (27/08) -- la carte
# affichait la liste des comptes, la version deployee, l'interpreteur, et le sort du
# dernier deploiement. Deux sujets, deux cartes.
#
#   « Comptes »      : qui a Vigie, et avec quels droits.
#   « Deploiement »  : ce que lancent les AUTRES comptes -- emplacement partage,
#                      interpreteur, taches de demarrage, dernier deploiement.
#
# Les deux restent dans le meme groupe : elles se lisent ensemble.
$depl = @()

# Installation lisible par les autres comptes ? Sinon, aucun autre compte ne peut demarrer
# Vigie -- et c'est le cas sur un poste de developpement. On le DIT sur la carte, avec le
# bouton qui corrige (D66 : une alerte porte toujours sa resolution).
$partagee = [bool](Get-SharedInstallPath)
if ($partagee) {
    # A JOUR ? Le numero de version ne suffit pas : deux « v0.1 » peuvent differer de
    # vingt commits. On compare donc le COMMIT, et on dit l'ecart (D84).
    $cmp = Compare-SharedInstall -Backend $backend
    $etat = 'accessible à tous les comptes'
    $niveau = 'ok'
    $detail = "Installation partagée : " + (Get-SharedInstallPath)
    if ($cmp) {
        $detail += [Environment]::NewLine + "Déployée : " + $cmp.there.version +
                   $(if ($cmp.there.commit) { " (" + $cmp.there.commit.Substring(0, [Math]::Min(8, $cmp.there.commit.Length)) + ")" } else { " (commit inconnu)" })
        $detail += [Environment]::NewLine + "Ce dépôt : " + $cmp.here.version +
                   $(if ($cmp.here.commit) { " (" + $cmp.here.commit.Substring(0, [Math]::Min(8, $cmp.here.commit.Length)) + ")" } else { "" })
        # LA VALEUR DIT CE QUE C'EST, la COULEUR dit que ca ne va pas, le DETAIL
        # explique (regle utilisateur du 27/08 : « juste la version en orange, ca
        # suffit a savoir qu'il y a un souci »). Une ligne de carte se lit d'un coup
        # d'oeil ; la phrase entiere tient dans l'infobulle.
        $etat = $cmp.there.version
        if ($cmp.same) {
            $pourquoi = "Elle correspond exactement au dépôt : les autres comptes lancent la même version que vous."
        } elseif ($null -ne $cmp.behind -and $cmp.behind -gt 0) {
            $niveau = 'warn'
            $pourquoi = "Elle est en retard de $($cmp.behind) commit(s) sur le dépôt : les autres comptes n'ont pas vos dernières corrections."
        } elseif (-not $cmp.there.commit) {
            $niveau = 'warn'
            $pourquoi = "Elle a été déployée avant que Vigie ne marque ses archives : impossible de dire à quel commit elle correspond."
        } else {
            $pourquoi = "Elle diffère du dépôt."
        }
        $detail = $pourquoi + [Environment]::NewLine + [Environment]::NewLine + $detail
    }
    # DEJA DEPLOYEE : ce qu'on propose est une MISE A JOUR, pas un deploiement --
    # « Deployer pour tous les comptes » ne veut plus rien dire une fois que c'est fait.
    $depl += New-Field -Key 'partage' -Label 'Installation partagée' -Value $etat -Kind 'text' -Status $niveau `
        -FixAction $(if ($niveau -eq 'warn') { 'vigie-update' } else { '' }) `
        -Help "Emplacement lisible par tous les comptes de la machine : leurs tâches de démarrage pointent dessus. Les autres comptes lancent CETTE version, pas celle du dépôt." `
        -Guide $detail
} else {
    # JAMAIS DEPLOYEE : la, c'est bien un PREMIER deploiement, et le bouton le dit.
    $depl += New-Field -Key 'partage' -Label 'Installation partagée' -Value 'Lisible par vous seul' -Kind 'text' -Status 'warn' `
        -FixAction 'vigie-update' `
        -Help "Les autres comptes ne peuvent pas lire cette installation : Vigie ne demarrerait pas chez eux." `
        -Guide ("Emplacement actuel : " + (Get-RepoRoot) + [Environment]::NewLine +
                "Le bouton installe cette version dans C:\Program Files\Sowapps\Vigie, lisible par tous les comptes, et conserve les reglages deja en place.")
}

# Meme obstacle, autre cause : l'application est bien partagee, mais l'INTERPRETEUR qui
# la lance ne l'est pas. Le dire ici, sinon activer un compte cree une tache qui echoue
# en silence a chaque ouverture de session (constate le 26/08 avec Famille).
$pwshPartage = Get-SharedPwshPath
$pwshCompte  = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwshPartage -and -not $pwshCompte) {
    # ABSENT, ce n'est pas « installe pour vous seul » : la carte doit dire lequel des
    # deux, sinon elle raconte une situation qui n'existe pas. Cas vecu le 26/08 : une
    # installation en portee machine a desinstalle le paquet du compte puis a echoue,
    # et la machine s'est retrouvee SANS PowerShell 7 -- la carte annoncait toujours
    # « installe pour vous seul ».
    $depl += New-Field -Key 'pwsh' -Label 'PowerShell 7' -Value 'Absent de la machine' -Kind 'text' -Status 'error' `
        -FixAction 'pwsh-install-machine' `
        -Help "PowerShell 7 n'est installé nulle part : Vigie ne redémarrera pas, ni pour vous ni pour les autres comptes. Les processus en cours survivent, mais le prochain démarrage échouera." `
        -Guide ("À faire tout de suite, dans un terminal ADMINISTRATEUR :" + [Environment]::NewLine +
                "  winget install --id Microsoft.PowerShell -e --scope machine" + [Environment]::NewLine +
                "À défaut, le paquet MSI : https://github.com/PowerShell/PowerShell/releases")
} elseif (-not $pwshPartage) {
    $depl += New-Field -Key 'pwsh' -Label 'PowerShell 7' -Value 'Installé pour vous seul' -Kind 'text' -Status 'warn' `
        -FixAction 'pwsh-install-machine' `
        -Help "Les tâches des autres comptes ont besoin d'un PowerShell 7 installé pour la MACHINE. Celui-ci vient du Store et n'existe que dans votre profil : leur tâche ne lancerait rien." `
        -Guide ("Interpréteur actuel : " + $pwshCompte + [Environment]::NewLine +
                "À faire une fois, en administrateur :" + [Environment]::NewLine +
                "  winget install --id Microsoft.PowerShell --scope machine" + [Environment]::NewLine +
                "Puis réactivez les comptes concernés.")
} else {
    $depl += New-Field -Key 'pwsh' -Label 'PowerShell 7' -Value 'Installé' -Kind 'text' -Status 'ok' `
        -Help "Tous les comptes peuvent lancer l'interpréteur : leurs tâches de démarrage fonctionnent." `
        -Guide ("Interpréteur des tâches : " + $pwshPartage)
}

if (-not $eleve) {
    $fields += New-Field -Key 'scope' -Label 'Détail des autres comptes' -Value 'Réservé à un administrateur' -Kind 'text' -Status 'neutral' `
        -Help "Windows protège le profil de chaque compte : leur détail n'est lisible que par un Vigie lancé en administrateur. Vigie ne montre rien de plus que ce que Windows laisse voir."
}

# TACHES MALADES : une tache qui vise un interpreteur ou une application disparus se
# lance et meurt en silence. La sonde ne repare RIEN (lecture seule) : elle constate, et
# porte le bouton qui repare (D66).
# --- QUEL ENVIRONNEMENT REPOND ----------------------------------------------
#
# Deux copies de Vigie coexistent sur un poste de developpement : le depot et
# l'installation partagee. Ne pas savoir laquelle repond fait perdre une heure sur un
# correctif deploye au mauvais endroit. La carte le dit, et signale deux ecarts :
# la machine ne tourne pas dans l'environnement qu'elle declare, ou une tache de compte
# lance l'autre environnement.
$declared = Get-DeclaredEnvironment -Backend $backend
$running  = Get-RunningEnvironment -Backend $backend
$envIssues = @()
if ($declared -ne $running) {
    $envIssues += ("la machine se déclare en « " + (Get-EnvironmentLabel -Environment $declared) +
                   " » mais Vigie tourne depuis « " + (Get-EnvironmentLabel -Environment $running) + " »")
}
foreach ($c in $comptes) {
    if (-not $c.task) { continue }
    try {
        $t = Get-ScheduledTask -TaskName $c.task -ErrorAction Stop
        $args = "$(@($t.Actions)[0].Arguments)"
        if ($args -match '-File\s+"([^"]+)"') {
            # Comparee a l'environnement DECLARE, pas a celui qui tourne : la declaration
            # est l'intention, et c'est elle qui fait autorite. Sinon, un serveur lance au
            # mauvais endroit rendrait toutes les taches « fautives ».
            $taskEnv = Get-PathEnvironment -Path $Matches[1]
            if ($taskEnv -ne $declared) {
                $envIssues += ($c.name + " démarre depuis « " + (Get-EnvironmentLabel -Environment $taskEnv) +
                               " » alors que la machine se déclare en « " +
                               (Get-EnvironmentLabel -Environment $declared) + " »")
            }
        }
    } catch { }
}

if ($envIssues.Count) {
    $depl += New-Field -Key 'env' -Label 'Environnement' `
        -Value ((Get-EnvironmentLabel -Environment $running) + " — " + $envIssues.Count.ToString() + " écart(s)") `
        -Kind 'text' -Status 'warn' -FixAction 'repair-tasks' `
        -Help "Le dépôt et l'installation partagée peuvent tourner sur la même machine. Vigie compare ce que la machine déclare, ce qui tourne réellement, et ce que lancent les tâches de démarrage : un écart signifie qu'un correctif peut atterrir là où personne ne le lit." `
        -Guide ($envIssues -join [Environment]::NewLine)
} else {
    $depl += New-Field -Key 'env' -Label 'Environnement' `
        -Value (Get-EnvironmentLabel -Environment $running) -Kind 'text' -Status 'ok' `
        -Help "Ce que la machine déclare, ce qui tourne et ce que lancent les tâches de démarrage concordent."
}

# HORS SERVICE et EN ATTENTE ne se disent pas de la meme facon. Une tache dont la
# structure est saine mais dont le dernier lancement a echoue n'est pas cassee : elle se
# confirmera au prochain demarrage du compte. L'annoncer en rouge etait excessif, et
# poussait a « reparer » ce qui n'avait rien a reparer.
$malades  = @($comptes | Where-Object { $_.taskAilment })
$enAttente = @($comptes | Where-Object { -not $_.taskAilment -and $_.taskPending })
if ($malades.Count) {
    $depl += New-Field -Key 'taches' -Label 'Démarrage automatique' `
        -Value ($malades.Count.ToString() + " tâche(s) hors service") -Kind 'text' -Status 'error' `
        -FixAction 'repair-tasks' `
        -Help "Une tâche de démarrage de Vigie ne peut plus lancer l'application : elle démarre et meurt aussitôt, sans message. Vigie ne se lancera pas à l'ouverture de session." `
        -Guide (($malades | ForEach-Object { $_.name + " : " + $_.taskAilment }) -join [Environment]::NewLine)
} elseif ($enAttente.Count) {
    # Pas de bouton : il n'y a rien a reparer. Seule la prochaine ouverture de session
    # du compte dira si le probleme est derriere nous.
    $depl += New-Field -Key 'taches' -Label 'Démarrage automatique' `
        -Value ($enAttente.Count.ToString() + " tâche(s) à confirmer") -Kind 'text' -Status 'warn' `
        -Help "La tâche est correctement installée, mais son dernier lancement s'est mal passé — ou elle n'a jamais tourné. Rien à réparer : c'est la prochaine ouverture de session de ce compte qui le dira." `
        -Guide (($enAttente | ForEach-Object { $_.name + " : " + $_.taskPending }) -join [Environment]::NewLine)
} else {
    $depl += New-Field -Key 'taches' -Label 'Démarrage automatique' `
        -Value 'Opérationnel' -Kind 'text' -Status 'ok' `
        -Help "Chaque compte qui a Vigie porte une tâche de démarrage saine."
}

# LE SORT DE LA DERNIERE OPERATION lancee depuis cette carte (D82). Une ligne verte
# quand elle a abouti, ROUGE avec son journal quand elle a echoue -- jamais rien.
$dernier = New-LastRunField -Module 'deployment'
if ($dernier) { $depl += $dernier }

# CE QUE VIGIE OCCUPE, tous comptes confondus (demande du 27/08). Une application qui
# surveille l'espace disque des autres doit dire ce qu'elle prend elle-meme.
$emp = Get-VigieFootprint -Backend $backend
$detailEmp = @()
if ($emp.programme) { $detailEmp += "Programme (partagé) : " + (Format-ByteSize -Bytes $emp.programme) + "  —  " + $emp.programmePath }
foreach ($x in @($emp.parCompte)) {
    $detailEmp += "Données de " + $x.name + $(if ($x.current) { " (vous)" } else { "" }) + " : " + (Format-ByteSize -Bytes $x.bytes)
}
if ($emp.sources) { $detailEmp += "Dépôt de développement : " + (Format-ByteSize -Bytes $emp.sources) + "  —  " + $emp.sourcesPath }
if (-not $emp.complet) { $detailEmp += "" ; $detailEmp += "Relevé partiel : les données des autres comptes ne sont lisibles que par un Vigie lancé en administrateur." }
$depl += New-Field -Key 'empreinte' -Label 'Stockage occupé' `
    -Value ((Format-ByteSize -Bytes $emp.total) + $(if (-not $emp.complet) { ' (au moins)' } else { '' })) `
    -Kind 'text' -Status 'neutral' `
    -Help "Tout ce que Vigie occupe sur cette machine : le programme partagé, les données de chaque compte, et le dépôt si vous développez." `
    -Guide ($detailEmp -join [Environment]::NewLine)

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

# --- Carte 2 : le DEPLOIEMENT ------------------------------------------------
# Une tache de fond lancee depuis cette carte (deploiement, installation de PowerShell)
# la garde en « operation en cours » jusqu'a la fin du processus.
$travail = Get-ModuleBusyMark -Module 'deployment'
$carteDepl = New-ModuleObject -Id 'deployment' -Theme 'accounts' -Label 'Déploiement' `
    -Status $(if (@($depl | Where-Object { "$($_.status)" -eq 'error' }).Count) { 'error' }
              elseif (@($depl | Where-Object { "$($_.status)" -eq 'warn' }).Count) { 'warn' }
              else { 'ok' }) `
    -Fields $depl `
    -Busy:([bool]$travail) -BusyAction $(if ($travail) { "$($travail.action)" } else { '' }) `
    -Actions @(
        New-Action -Id 'vigie-update' -Label 'Mettre à jour l''installation' -Kind 'confirm' -Severity 'fix' -Confirm `
            -BusyLabel 'Mise à jour…' `
            -Help "Déploie la version actuelle vers l'installation partagée, puis relance Vigie avec." `
            -Impact ("Deux étapes enchaînées : copie vers l'emplacement partagé (avec pose d'un tag de version), " +
                     "puis relance du tray ET du serveur. L'interface se coupe quelques secondes et se reconnecte seule. " +
                     "Réglages, historique et journaux sont conservés — ils vivent dans votre profil, pas dans l'installation.") `
            -Usage ("Quand l'installation partagée est en retard sur ce dépôt : les autres comptes lancent alors une " +
                    "version plus ancienne que la vôtre. C'est aussi le premier déploiement, si l'installation n'existe pas encore.") `
            -Reversible ("Le déploiement se défait en déployant une version antérieure. Si la copie échoue, la relance " +
                         "N'A PAS LIEU : l'ancienne version continue de tourner.")
        New-Action -Id 'repair-tasks' -Label 'Vérifier le démarrage de Vigie' -Kind 'immediate' -Severity 'fix' `
            -BusyLabel 'Réparation…' `
            -Help "Réécrit les tâches de démarrage de Vigie qui ne fonctionnent plus (interpréteur ou application déplacés). Ne touche à rien d'autre sur la machine."
    )

@($carteComptes, $carteDepl)
