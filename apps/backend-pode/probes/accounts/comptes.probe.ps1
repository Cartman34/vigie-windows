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

    $fields += New-Field -Key ('acc-' + ($c.name -replace '[^A-Za-z0-9]', '')) `
        -Label ($c.name + $(if ($c.current) { ' (vous)' } else { '' })) `
        -Value ($etat -join ' - ') -Kind 'text' -Status 'neutral' `
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
    $depl += New-Field -Key 'partage' -Label 'Installation' -Value $etat -Kind 'text' -Status $niveau `
        -FixAction $(if ($niveau -eq 'warn') { 'deploy-shared' } else { '' }) `
        -Help "Emplacement lisible par tous les comptes de la machine : leurs tâches de démarrage pointent dessus. Les autres comptes lancent CETTE version, pas celle du dépôt." `
        -Guide $detail
} else {
    $depl += New-Field -Key 'partage' -Label 'Installation' -Value 'Lisible par vous seul' -Kind 'text' -Status 'warn' `
        -FixAction 'deploy-shared' `
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
$malades = @($comptes | Where-Object { $_.taskAilment })
if ($malades.Count) {
    $depl += New-Field -Key 'taches' -Label 'Démarrage automatique' `
        -Value ($malades.Count.ToString() + " tâche(s) hors service") -Kind 'text' -Status 'error' `
        -FixAction 'repair-tasks' `
        -Help "Une tâche de démarrage de Vigie ne peut plus lancer l'application : elle démarre et meurt aussitôt, sans message. Vigie ne se lancera pas à l'ouverture de session." `
        -Guide (($malades | ForEach-Object { $_.name + " : " + $_.taskAilment }) -join [Environment]::NewLine)
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
        New-Action -Id 'deploy-shared' -Label 'Déployer pour tous les comptes' -Kind 'confirm' -Severity 'fix' -Confirm `
            -BusyLabel 'Déploiement…' `
            -Help "Installe cette version dans C:\Program Files\Sowapps\Vigie, lisible par tous les comptes de la machine."
        New-Action -Id 'repair-tasks' -Label 'Réparer le démarrage de Vigie' -Kind 'immediate' -Severity 'fix' `
            -BusyLabel 'Réparation…' `
            -Help "Réécrit les tâches de démarrage de Vigie qui ne fonctionnent plus (interpréteur ou application déplacés). Ne touche à rien d'autre sur la machine."
    )

@($carteComptes, $carteDepl)
