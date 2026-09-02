# @author Florent HAZARD <f.hazard@sowapps.com>
<# Sonde : LE DEPLOIEMENT de Vigie sur cette machine. LECTURE SEULE.

   Ce que lancent les AUTRES comptes : emplacement partage, version en place, interpreteur,
   taches de demarrage, sort du dernier deploiement.

   POURQUOI ELLE VIT SEULE, DANS SON PROPRE MODULE. Elle etait rendue par la sonde des
   comptes, qui est declaree PAR COMPTE (elle ecrit « vous » a cote d'un nom). Or une sonde
   par compte n'est JAMAIS differee vers le rafraichissement de fond : elle est calculee
   DANS la requete, parce que le rafraichissement de fond tourne sans session et ne saurait
   pas pour qui garder son resultat.

   Cette carte-ci ne parle de personne en particulier : elle compare une installation a sa
   source. La laisser dans la sonde par compte la rendait obligatoire dans chaque requete,
   avec ce qu'elle coute -- lecture des comptes, etat des taches, synchronisation du clone.
   Le 31/08, /api/v1/state mettait jusqu'a 52 secondes. Separee, elle redevient differable :
   la reponse part avec la valeur connue, le recalcul se fait derriere.

   Le groupe ne change pas : les deux cartes se lisent ensemble, sous « Comptes ». #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$elevated   = [bool](Test-IsElevated)
$accounts = @(Get-UserAccounts)
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

if (-not $elevated) {
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
foreach ($c in $accounts) {
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
$malades  = @($accounts | Where-Object { $_.taskAilment })
$enAttente = @($accounts | Where-Object { -not $_.taskAilment -and $_.taskPending })
if ($malades.Count) {
    $depl += New-Field -Key 'taches' -Label 'Démarrage automatique' `
        -Value ($(if ($malades.Count -eq 1) { "Ne démarre pas — " + $malades[0].name }
                  else { "Ne démarre pas — " + $malades.Count.ToString() + " comptes" })) -Kind 'text' -Status 'error' `
        -FixAction 'repair-tasks' `
        -Help "Une tâche de démarrage de Vigie ne peut plus lancer l'application : elle démarre et meurt aussitôt, sans message. Vigie ne se lancera pas à l'ouverture de session." `
        -Guide (($malades | ForEach-Object { $_.name + " : " + $_.taskAilment }) -join [Environment]::NewLine)
} elseif ($enAttente.Count) {
    # Pas de bouton : il n'y a rien a reparer. Seule la prochaine ouverture de session
    # du compte dira si le probleme est derriere nous.
    <#
        « 1 tache(s) a confirmer » ne dit rien a personne : confirmer par qui, quoi,
        comment ? Une valeur de carte se comprend SANS ouvrir l'aide. On dit donc ce qui
        est vrai : Vigie n'a pas encore demarre chez ce compte.

        NEUTRE, PAS « A SURVEILLER » : il n'y a rien a faire et rien a reparer. Un
        avertissement reclame une action (D66) ; celui-ci n'en avait aucune a proposer, et
        poussait a « reparer » ce qui va bien.

        LE COMMENTAIRE VIT AU-DESSUS DE L'INSTRUCTION. Glisse entre un accent grave de
        continuation et le parametre suivant, il COUPE l'appel : la sonde levait
        « missing mandatory parameters: Value Kind » et ne rendait plus aucune carte.
    #>
    $depl += New-Field -Key 'taches' -Label 'Démarrage automatique' `
        -Value ($(if ($enAttente.Count -eq 1) { "Jamais démarrée — " + $enAttente[0].name }
                  else { "Jamais démarrée — " + $enAttente.Count.ToString() + " comptes" })) -Kind 'text' -Status 'neutral' `
        -Help "Vigie est bien installée pour ce compte, mais elle ne s'y est pas encore lancée — soit il n'a pas ouvert de session depuis, soit son dernier démarrage s'est mal passé. Il n'y a rien à réparer : la prochaine ouverture de session de ce compte le dira." `
        -Guide (($enAttente | ForEach-Object { $_.name + " : " + $_.taskPending }) -join [Environment]::NewLine)
} else {
    $depl += New-Field -Key 'taches' -Label 'Démarrage automatique' `
        -Value 'Opérationnel' -Kind 'text' -Status 'ok' `
        -Help "Chaque compte qui a Vigie porte une tâche de démarrage saine."
}

<#
    LES DEUX VERSIONS DE LA CONFIRMATION : d'ou l'on vient, ou l'on va.

    « Deploie la version actuelle vers l'installation partagee » ne dit pas laquelle vers
    laquelle : on cliquait sans savoir si l'on avancait de deux commits ou si l'on ecrasait
    une version plus recente. La fenetre montre donc deux pastilles, ancienne -> nouvelle.

    CE BLOC AVAIT DISPARU quand la carte Deploiement est sortie dans sa propre sonde : il
    etait reste dans celle des comptes, l'action continuait de citer des variables VIDES,
    et les deux pastilles ne s'affichaient plus. Rien ne l'avait signale -- une variable
    absente ne fait pas d'erreur en PowerShell.

    LE COMMIT N'EST MONTRE QU'EN DEVELOPPEMENT : en production, deux versions se
    distinguent par leur numero, c'est a cela qu'il sert. En developpement le numero ne
    bouge pas entre deux commits, et « v0.1.57 vers v0.1.57 » ne dirait rien.
#>
$court = { param($c) if ($c) { $c.Substring(0, [Math]::Min(8, $c.Length)) } else { '' } }
$estDev = ((Get-DeclaredStage -Backend $backend) -eq 'dev')
$deVersion = ''; $versVersion = ''; $deNote = ''; $versNote = ''
if ($cmp) {
    $deVersion   = "$($cmp.there.version)"
    $versVersion = "$($cmp.here.version)"
    if ($estDev) {
        $deNote   = & $court $cmp.there.commit
        $versNote = & $court $cmp.here.commit
    }
} else {
    $deVersion   = 'rien'
    $versVersion = 'première installation'
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

@($carteDepl)
