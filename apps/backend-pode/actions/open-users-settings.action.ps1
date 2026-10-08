# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @libelle: Gerer les comptes | dialog | info   -- affiche quand un champ cite cette action (D66)
<# An action: it opens Settings > Users.

   Intent: be known to the controller and to the rights policy even though THE INTERFACE handles it (the front
   end opens the panel with no round trip to the server), and answer something sensible to a direct call instead
   of a 404. Usage: it is cited by the Accounts card. #>
param([string]$Module, [hashtable]$Params)
@{
    message = "Les comptes avec lesquels Vigie démarre se choisissent dans Paramètres > Utilisateurs."
    result  = @{ ok = $true; ui = 'settings:utilisateurs' }
}
