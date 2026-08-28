# @droits: tous   -- n'exige aucun privilege que Windows n'accorde deja (D65)
# @libelle: Gestionnaire de périphériques | manual | info   -- affiche quand un champ cite cette action (D66)
<# Action : ouvre le Gestionnaire de peripheriques de Windows.

   Resolution proposee quand un adaptateur graphique manque ou que l'outil du pilote est
   absent : c'est la ou Windows montre l'etat du materiel et propose la mise a jour du
   pilote. Un compte standard peut l'ouvrir (Windows le passe en lecture seule) : on ne
   lui interdit donc pas ce que Windows lui accorde (D65). #>
param([string]$Module, [hashtable]$Params)
try {
    Start-Process 'mmc.exe' -ArgumentList 'devmgmt.msc'
    @{ message = "Gestionnaire de périphériques ouvert : section « Cartes graphiques »."; result = @{ ok = $true } }
} catch {
    @{ message = "Impossible d'ouvrir le Gestionnaire de périphériques : $($_.Exception.Message)"; result = @{ ok = $false } }
}
