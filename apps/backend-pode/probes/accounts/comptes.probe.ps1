<# Sonde : les COMPTES de cet ordinateur. LECTURE SEULE.

   Une LIGNE PAR COMPTE (choix utilisateur) : le nom a gauche, et en face l'essentiel --
   Vigie active ou non, et le type de compte. Le reste (derniere session, poids des
   donnees) tient dans l'action « Details des comptes » : une carte se lit d'un coup d'oeil,
   elle ne se deplie pas pour livrer l'information principale.

   VRAIS COMPTES SEULEMENT : les comptes techniques (sans profil humain -- bacs a sable,
   comptes de service) sont masques par defaut, mais leur nombre est DIT et un parametre
   les fait reapparaitre. Rien ne disparait en silence (D59).

   CE QU'ELLE MONTRE DEPEND DE QUI REGARDE (D65) : le detail des autres comptes n'existe
   que si Vigie tourne en administrateur -- Windows protege les profils, Vigie ne contourne
   pas cette regle.

   La GESTION (activer Vigie pour un compte) vit dans Parametres > Utilisateurs ; le bouton
   de la carte y mene. #>
$backend = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $backend 'lib/common.ps1')

$dormant = [int](Get-ModuleSetting -Unit 'accounts' -Key 'DormantDays')
if (-not $dormant) { $dormant = 90 }
$montrerTechniques = [bool](Get-ModuleSetting -Unit 'accounts' -Key 'ShowTechnicalAccounts')

$eleve   = [bool](Test-IsElevated)
$tous    = @(Get-VigieAccounts)
$masques = @($tous | Where-Object { $_.technical })
$comptes = if ($montrerTechniques) { $tous } else { @($tous | Where-Object { -not $_.technical }) }

$fields = @()

# UNE LIGNE PAR COMPTE : nom a gauche, etat a droite.
foreach ($c in ($comptes | Sort-Object @{ Expression = { -not $_.current } }, name)) {
    $etat = @()
    $etat += $(if ($c.enabled) { 'Vigie activée' } else { 'Vigie inactive' })
    $etat += $(if ($c.admin) { 'administrateur' } else { 'standard' })

    $aide = @()
    $aide += $(if ($c.enabled) { "Vigie démarre à l'ouverture de session de ce compte." }
               else { "Vigie ne démarre pas avec ce compte. Pour l'activer : Paramètres > Utilisateurs." })
    $aide += $(if ($c.admin) { "Compte administrateur : les actions qui modifient le système lui sont permises." }
               else { "Compte standard : Vigie lui refuse les actions administrateur, comme le ferait Windows." })
    if ($c.current) { $aide += "C'est le compte avec lequel vous utilisez Vigie en ce moment." }

    $fields += New-Field -Key ('acc-' + ($c.name -replace '[^A-Za-z0-9]', '')) `
        -Label ($c.name + $(if ($c.current) { ' (vous)' } else { '' })) `
        -Value ($etat -join ' · ') -Kind 'text' -Status 'neutral' `
        -Help ($aide -join ' ')
}

# Ce qui est masque est DIT (jamais silencieux).
if (-not $montrerTechniques -and $masques.Count -gt 0) {
    $fields += New-Field -Key 'hidden' -Label 'Comptes techniques masqués' -Value ($masques.Count) -Kind 'number' -Status 'neutral' `
        -Help "Comptes sans profil humain (bacs à sable, comptes de service). Pour les afficher : Paramètres > Modules > Comptes." `
        -Guide (($masques | ForEach-Object { "- $($_.name)" }) -join [Environment]::NewLine)
}

if (-not $eleve) {
    $fields += New-Field -Key 'scope' -Label 'Détail des autres comptes' -Value 'réservé à un administrateur' -Kind 'text' -Status 'neutral' `
        -Help "Windows protège le profil de chaque compte : leur détail n'est lisible que par un Vigie lancé en administrateur. Vigie ne montre rien de plus que ce que Windows laisse voir."
}

New-ModuleObject -Id 'accounts' -Theme 'accounts' -Label 'Comptes' -Status 'ok' -Fields $fields -Actions @(
    New-Action -Id 'accounts-details' -Label 'Détails des comptes' -Kind 'immediate' -Severity 'info' `
        -Help "Dernière ouverture de session, comptes dormants, poids des données Vigie de chacun. Demande un compte administrateur."
    New-Action -Id 'open-users-settings' -Label 'Gérer les comptes' -Kind 'dialog' -Severity 'info' `
        -Help "Ouvre Paramètres > Utilisateurs : choisir les comptes avec lesquels Vigie démarre."
)
