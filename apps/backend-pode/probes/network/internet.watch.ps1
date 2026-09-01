# @author Florent HAZARD <f.hazard@sowapps.com>
<# RELEVE : Internet repond-il ? Rend « oui » ou « non ». Rien d'autre.

   BON MARCHE, c'est la condition : ce fichier tourne toutes les minutes, en permanence,
   meme sans session ouverte. Un ping vers une adresse qui repond toujours suffit -- on ne
   mesure ni la latence ni le debit ici, la carte Reseau s'en charge quand on la demande.

   La valeur rendue est COMPARABLE : c'est son changement qui fait evenement, et
   l'evenement fait recalculer la carte Reseau. Voir doc/progress/targeting/surveillance.md.
#>
$ok = $false
try {
    # -Quiet : un booleen, pas un objet. 1 tentative, 1 seconde : on veut savoir si ca
    # repond, pas combien de temps ca met.
    $ok = [bool](Test-Connection -TargetName '1.1.1.1' -Count 1 -TimeoutSeconds 1 -Quiet -ErrorAction Stop)
} catch { $ok = $false }
if ($ok) { 'oui' } else { 'non' }
