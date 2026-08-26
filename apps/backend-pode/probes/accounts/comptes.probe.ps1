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
    $fields += New-Field -Key 'aucun' -Label 'Comptes' -Value 'aucun compte utilisateur' -Kind 'text' -Status 'neutral' `
        -Help "Aucun compte de cet ordinateur n'a encore ouvert de session."
}

# Installation lisible par les autres comptes ? Sinon, aucun autre compte ne peut demarrer
# Vigie -- et c'est le cas sur un poste de developpement. On le DIT sur la carte, avec le
# bouton qui corrige (D66 : une alerte porte toujours sa resolution).
$partagee = [bool](Get-SharedInstallPath)
if ($partagee) {
    $fields += New-Field -Key 'partage' -Label 'Installation' -Value 'accessible a tous les comptes' -Kind 'text' -Status 'ok' `
        -Help "Emplacement lisible par tous les comptes de la machine : leurs taches de demarrage pointent dessus." `
        -Guide ("Installation partagee : " + (Get-SharedInstallPath))
} else {
    $fields += New-Field -Key 'partage' -Label 'Installation' -Value 'lisible par vous seul' -Kind 'text' -Status 'warn' `
        -FixAction 'deploy-shared' `
        -Help "Les autres comptes ne peuvent pas lire cette installation : Vigie ne demarrerait pas chez eux." `
        -Guide ("Emplacement actuel : " + (Get-RepoRoot) + [Environment]::NewLine +
                "Le bouton installe cette version dans C:\Program Files\Sowapps\Vigie, lisible par tous les comptes, et conserve les reglages deja en place.")
}

# Meme obstacle, autre cause : l'application est bien partagee, mais l'INTERPRETEUR qui
# la lance ne l'est pas. Le dire ici, sinon activer un compte cree une tache qui echoue
# en silence a chaque ouverture de session (constate le 26/08 avec Famille).
$pwshPartage = Get-SharedPwshPath
if (-not $pwshPartage) {
    $fields += New-Field -Key 'pwsh' -Label 'PowerShell 7' -Value 'installe pour vous seul' -Kind 'text' -Status 'warn' `
        -FixAction 'pwsh-install-machine' `
        -Help "Les taches des autres comptes ont besoin d'un PowerShell 7 installe pour la MACHINE. Celui-ci vient du Store et n'existe que dans votre profil : leur tache ne lancerait rien." `
        -Guide ("Interpreteur actuel : " + ((Get-Command pwsh -ErrorAction SilentlyContinue).Source) + [Environment]::NewLine +
                "A faire une fois, en administrateur :" + [Environment]::NewLine +
                "  winget install --id Microsoft.PowerShell --scope machine" + [Environment]::NewLine +
                "Puis reactivez les comptes concernes.")
} else {
    $fields += New-Field -Key 'pwsh' -Label 'PowerShell 7' -Value 'installe pour la machine' -Kind 'text' -Status 'ok' `
        -Help "Tous les comptes peuvent lancer l'interpreteur : leurs taches de demarrage fonctionnent." `
        -Guide ("Interpreteur des taches : " + $pwshPartage)
}

if (-not $eleve) {
    $fields += New-Field -Key 'scope' -Label 'Détail des autres comptes' -Value 'réservé à un administrateur' -Kind 'text' -Status 'neutral' `
        -Help "Windows protège le profil de chaque compte : leur détail n'est lisible que par un Vigie lancé en administrateur. Vigie ne montre rien de plus que ce que Windows laisse voir."
}

New-ModuleObject -Id 'accounts' -Theme 'accounts' -Label 'Comptes' -Status 'ok' -Fields $fields -Actions @(
    New-Action -Id 'accounts-details' -Label 'Détails des comptes' -Kind 'immediate' -Severity 'info' `
        -Help "Dernière ouverture de session et poids des données Vigie de chacun. Demande un compte administrateur."
    New-Action -Id 'deploy-shared' -Label 'Déployer pour tous les comptes' -Kind 'confirm' -Severity 'fix' -Confirm `
        -BusyLabel 'Déploiement…' `
        -Help "Installe cette version dans C:\Program Files\Sowapps\Vigie, lisible par tous les comptes de la machine."
    New-Action -Id 'accounts-refresh' -Label 'Actualiser la liste' -Kind 'immediate' -Severity 'neutral' `
        -BusyLabel 'Relevé…' `
        -Help "Refait le relevé des comptes. La liste est mémorisée 24 h : elle ne change qu'exceptionnellement."
    New-Action -Id 'open-users-settings' -Label 'Gérer les comptes' -Kind 'dialog' -Severity 'info' `
        -Help "Ouvre Paramètres > Utilisateurs : choisir les comptes avec lesquels Vigie démarre."
)
