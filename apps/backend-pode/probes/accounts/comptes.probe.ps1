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
        # LA VALEUR DIT CE QUE C'EST, la COULEUR dit que ca ne va pas, le DETAIL
        # explique (regle utilisateur du 27/08 : « juste la version en orange, ca
        # suffit a savoir qu'il y a un souci »). Une ligne de carte se lit d'un coup
        # d'oeil ; la phrase entiere tient dans l'infobulle.
        $etat = $cmp.there.version
        $detail += [Environment]::NewLine + "Déployée : " + $cmp.there.version +
                   $(if ($cmp.there.commit) { " (" + $cmp.there.commit.Substring(0, [Math]::Min(8, $cmp.there.commit.Length)) + ")" } else { " (commit inconnu)" })

        <#
            A QUOI COMPARE-T-ON ? La question a une reponse differente selon la machine, et
            l'ancienne version n'en posait aucune : elle comparait a « ici », qui EST
            l'installation quand l'app serveur tourne dedans. Elle se declarait donc
            conforme a elle-meme, quoi qu'il arrive.

            On DIT desormais la reference, et quand il n'y en a pas, on dit ca aussi --
            plutot que de rassurer sans rien savoir.
        #>
        if ($cmp.reference -eq 'clone') {
            $detail += [Environment]::NewLine + "Source : " + $cmp.here.version +
                       $(if ($cmp.here.commit) { " (" + $cmp.here.commit.Substring(0, [Math]::Min(8, $cmp.here.commit.Length)) + ")" } else { "" })
            $detail += [Environment]::NewLine + "Synchronisé depuis : " + $cmp.remote
            # LE DEPOT EST DECLARE, MAIS EST-IL LISIBLE ? Le compte qui fait tourner Vigie
            # n'est pas celui qui developpe : il peut n'avoir aucun droit sur le dossier de
            # travail, ou git peut refuser un dépôt appartenant à quelqu'un d'autre. On le
            # DIT, avec le mot de git : « Elle diffère du dépôt » laissait croire à un
            # écart de code alors qu'on n'avait rien pu lire du tout.
            if ($cmp.here.error) {
                $niveau = 'warn'
                $why = "La source n'a pas pu être lue : " + $cmp.here.error +
                            " Tant qu'elle est illisible, impossible de dire si l'installation est à jour."
            } elseif ($cmp.same) {
                $why = "Elle correspond exactement à la source : les autres comptes lancent la même version que vous."
            } elseif ($null -ne $cmp.behind -and $cmp.behind -gt 0) {
                $niveau = 'warn'
                $why = "Elle est en retard de $($cmp.behind) commit(s) sur la source : les autres comptes n'ont pas vos dernières corrections."
            } elseif (-not $cmp.there.commit) {
                $niveau = 'warn'
                $why = "Elle a été déployée avant que Vigie ne marque ses archives : impossible de dire à quel commit elle correspond."
            } else {
                $niveau = 'warn'
                $why = "Elle diffère de la source."
            }
        } elseif ($cmp.reference -eq 'publiee') {
            $detail += [Environment]::NewLine + "Dernière version publiée : " + $cmp.here.version
            if ($cmp.same) {
                $why = "C'est la dernière version publiée : il n'y a rien à mettre à jour."
            } else {
                $niveau = 'warn'
                $why = "Une version plus récente est publiée ($($cmp.here.version))."
            }
        } else {
            # NI DEPOT, NI RESEAU. On ne sait pas, et on le dit : « conforme » par defaut
            # est le pire des verdicts, il rassure sans rien savoir.
            $niveau = 'neutral'
            $why = "Impossible de dire si elle est à jour : aucun dépôt sur ce poste, et la liste des versions publiées n'a pas pu être consultée."
        }
        $detail = $why + [Environment]::NewLine + [Environment]::NewLine + $detail
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
# VIGIE TOURNE TOUJOURS DEPUIS L'INSTALLATION PARTAGEE, developpement compris. Seule la
# SOURCE de ce qu'on y deploie change : une version publiee en production, une branche du
# depot en developpement -- et l'ecart se lit alors dans le numero de version lui-meme
# (« v0.1.27+3 »), pas dans un emplacement.
#
# Je signalais donc un ecart permanent et sans objet sur un poste de developpement : « la
# machine se declare Developpement mais Vigie tourne depuis Production ». Il n'y avait
# rien a reparer, et la carte passait au orange pour un fonctionnement normal.
#
# CE QUI RESTE UN ECART : une tache qui lance le DEPOT. Le dossier de travail peut etre
# illisible pour les autres comptes -- « Famille » n'a aucun droit sur C:\EspaceRestreint,
# et VigieService non plus -- et il peut bouger. Une tache qui pointe dessus ne demarre
# rien, un jour ou l'autre.
$declared = Get-DeclaredStage -Backend $backend
$running  = Get-RunningStage -Backend $backend
$envIssues = @()
foreach ($c in $comptes) {
    if (-not $c.task) { continue }
    try {
        $t = Get-ScheduledTask -TaskName $c.task -ErrorAction Stop
        $args = "$(@($t.Actions)[0].Arguments)"
        if ($args -match '-File\s+"([^"]+)"') {
            if ((Get-PathStage -Path $Matches[1]) -ne 'prod') {
                $envIssues += ($c.name + " démarre depuis le dépôt de travail, pas depuis l'installation partagée")
            }
        }
    } catch { }
}

# LE CHAMP S'APPELLE « STAGE » : « environnement » ne disait pas de quoi on parlait -- ce
# reglage, le serveur, ou l'ordinateur entier ? Et la valeur est ce que l'ordinateur
# DECLARE, pas l'emplacement du code qui tourne : celui-ci est toujours le meme, donc sans
# information, et trompeur des qu'on le comparait a la declaration.
$aide = "Le stage déclaré par cet ordinateur : développement ou production. " +
        "Il conditionne le marquage des versions, pas la provenance du code — celle-ci est un réglage à part. Vigie tourne toujours depuis l'installation partagée : " +
        "une tâche qui lance le dépôt de travail ne démarrera pas chez un compte qui n'y a pas accès."
if ($envIssues.Count) {
    $depl += New-Field -Key 'env' -Label 'Stage' `
        -Value ((Get-StageLabel -Stage $declared) + " — " + $envIssues.Count.ToString() + " écart(s)") `
        -Kind 'text' -Status 'warn' -FixAction 'repair-tasks' `
        -Help $aide `
        -Guide ($envIssues -join [Environment]::NewLine)
} else {
    $depl += New-Field -Key 'env' -Label 'Stage' `
        -Value (Get-StageLabel -Stage $declared) -Kind 'text' -Status 'ok' `
        -Help $aide `
        -Guide ("Toutes les tâches de démarrage lancent l'installation partagée." + [Environment]::NewLine +
                "Vigie répond depuis : " + (Get-StageLabel -Stage $running))
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
        # LES TEXTES DE LA CONFIRMATION. « Ce que ca change » dit ce qui CHANGE, pas ce qui
        # se passe -- le deroule est montre juste au-dessus par -Steps. Et sans notre
        # vocabulaire interne : « tag de version », « tray », « depot » ne veulent rien
        # dire pour qui utilise Vigie. « Revenir en arriere » repond OUI, puis comment.
        #
        # ATTENTION : ces commentaires sont ICI et pas au milieu de l'appel. Un commentaire
        # place apres un backtick de continuation la COUPE : la ligne suivante devient
        # une commande a part, et PowerShell repond « le terme '-Impact' n'est pas
        # reconnu ». Constate le 29/08, sonde cassee en production.
        New-Action -Id 'vigie-update' -Label 'Mettre à jour l''installation' -Kind 'confirm' -Severity 'fix' -Confirm `
            -BusyLabel 'Mise à jour…' `
            -Help "Déploie la version actuelle vers l'installation partagée, puis relance Vigie avec." `
            -From $deVersion -To $versVersion -FromNote $deNote -ToNote $versNote `
            -Steps @('Copie vers Program Files', 'Redémarrage du serveur', 'Vigie à jour') `
            -Impact ("Tous les comptes de la machine passeront à cette version, y compris le vôtre. " +
                     "Vos réglages, votre historique et vos journaux ne bougent pas : ils vivent dans votre " +
                     "profil, pas dans l'installation. Vigie se coupe quelques secondes et revient seule.") `
            -Usage ("Quand les autres comptes utilisent encore une version plus ancienne que la vôtre. " +
                    "C'est aussi ce qui installe Vigie pour tout le monde, la première fois.") `
            -Reversible ("Oui : en déployant une version plus ancienne. Et si la copie échoue, rien n'est " +
                         "relancé — la version en place continue de tourner.")
        New-Action -Id 'repair-tasks' -Label 'Réparer le démarrage de Vigie' -Kind 'immediate' -Severity 'fix' `
            -BusyLabel 'Réparation…' `
            -Help "Réécrit les tâches de démarrage de Vigie qui ne fonctionnent plus (interpréteur ou application déplacés). Ne touche à rien d'autre sur la machine."
    )

@($carteComptes, $carteDepl)
