# Vigie — raccourci pour Claude Code

**Ce fichier est facultatif, et ne contient aucune règle.** Claude Code le charge tout
seul et le garde en contexte, y compris après une compression : c'est son seul intérêt.
Tout autre agent l'ignorera — et ne perdra rien, parce que ce qu'il faut savoir vit dans
le dépôt, jamais ici.

## À faire, dans cet ordre

1. **Lire `doc/en/agent-working/briefing.md`, et appliquer ce qu'il dit.** C'est le point
   d'entrée du projet, quel que soit l'agent. Il ouvre une chaîne — disciplines,
   décisions, conception — dont chaque maillon oblige au suivant.
2. **Au retour d'une compression de contexte**, avant toute conclusion, toute suppression
   et toute livraison :

   ```
   pwsh -File scripts/dev/reprise.ps1
   ```

   Un résumé n'est pas une source : il dit ce qui a été fait, pas ce qui est.

La documentation du dépôt n'est pas une référence qu'on consulte en cas de doute : c'est
la manière de travailler ici, et elle prévaut sur toute habitude, tout souvenir et tout
résumé.
