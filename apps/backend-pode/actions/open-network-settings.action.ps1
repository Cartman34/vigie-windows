# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @libelle: Paramètres Wi-Fi | manual | info   -- affiche quand un champ cite cette action (D66)
<# Action : ouvre les parametres Wi-Fi de Windows.

   Resolution proposee quand l'association Wi-Fi decroche : c'est la que se choisit le
   reseau, que se refait une connexion, ou que se verifie l'adaptateur. Vigie ne coupe ni
   ne reconnecte le lien a la place de l'utilisateur : sur un poste distant, une
   reconnexion ratee laisse la machine sans reseau. #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'ms-settings:network-wifi'
    @{ message = "Paramètres Wi-Fi ouverts."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir les paramètres Wi-Fi : $($_.Exception.Message)"; result = @{ ok = $false } }
}
