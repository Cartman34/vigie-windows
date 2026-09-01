# @author Florent HAZARD <f.hazard@sowapps.com>
# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @libelle: Gerer les comptes | dialog | info   -- affiche quand un champ cite cette action (D66)
<# Action : ouvre Parametres > Utilisateurs.

   Elle est traitee PAR L'INTERFACE (le front ouvre le panneau sans aller-retour serveur).
   Ce fichier existe pour que l'action soit connue du controleur et de la politique de
   droits, et pour qu'un appel direct reponde quelque chose de sense au lieu d'un 404. #>
param([string]$Module, [hashtable]$Params)
@{
    message = "Ouvrez Paramètres > Utilisateurs pour choisir les comptes avec lesquels Vigie démarre."
    result  = @{ ok = $true; ui = 'settings:utilisateurs' }
}
