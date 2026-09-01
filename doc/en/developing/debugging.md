# Déboguer — une seule démarche, la même à chaque fois

Auteur : Florent HAZARD <f.hazard@sowapps.com>

Quand quelque chose ne marche pas, la question « comment on regarde, déjà ? » ne doit pas se reposer. Elle a une
réponse, et c'est un script : [`scripts/dev/debug.ps1`](../../../scripts/dev/debug.ps1).

```powershell
pwsh -File scripts/dev/debug.ps1                     # ce qu'on peut déboguer
pwsh -File scripts/dev/debug.ps1 probe gaming        # une sonde, exécutée pour de vrai
pwsh -File scripts/dev/debug.ps1 sentinel            # les sentinelles déclarées
pwsh -File scripts/dev/debug.ps1 sentinel internet   # sa valeur maintenant + son historique
pwsh -File scripts/dev/debug.ps1 server              # l'app serveur et son journal
pwsh -File scripts/dev/debug.ps1 client              # l'app cliente et son journal
pwsh -File scripts/dev/debug.ps1 install             # la dernière installation
pwsh -File scripts/dev/debug.ps1 card gaming         # la carte telle que Vigie la rend
```

Chaque cible fait la même chose, dans le même ordre : elle **dit ce qu'elle lance**, elle le lance de la manière
standard, puis elle montre **où est le journal** et ses dernières lignes.

## Les quatre règles qui valent pour tout

**1. Dans une vraie console, sans rediriger la sortie.** Une sortie redirigée perd ses couleurs *et* s'affiche avec un
tour de retard : le programme paraît figé alors qu'il avance. Pire, une console Windows en **mode sélection** (un clic
dans la fenêtre) met le programme en pause à sa prochaine écriture — il attend une touche, rien d'autre. Le 01/09,
l'installation a semblé bloquée vingt minutes pour cette seule raison ; **Échap** ou **Entrée** l'a relancée.

**2. Jamais un second journal.** Le programme écrit déjà le sien. En ajouter un par-dessus donne deux versions du même
récit, des lignes en double, et une occasion de se tromper de fichier. Si ce journal ne dit pas assez, on **améliore
celui-là**.

**3. Ce qui est illisible ici se demande à Vigie.** Depuis une session ordinaire, le profil du compte de service, ses
journaux, ses tâches et l'historique sont **refusés** — et un refus ne dit rien du poste, seulement de mes droits.
L'app serveur, elle, voit tout : [`ask-vigie.ps1`](../../../scripts/dev/ask-vigie.ps1) emprunte le chemin de l'app
cliente et rend les faits **tels que Vigie les voit**.

**4. Une action ou un worker ne s'exécute pas pour voir.** Les lancer pour de vrai est un test d'**intégration** : il se
**demande** à l'utilisateur, à chaque fois (**D62**, **D63**).

## Ce qui prouve quoi

| Ce qu'on veut savoir | Ce qui le prouve |
|---|---|
| Une sonde rend-elle ce qu'on croit ? | `debug.ps1 probe <id>` — elle s'exécute vraiment, on **constate** sa sortie (D43) |
| Une branche rare marche-t-elle ? | `VIGIE_FAKE_<QUOI>` — voir [modules.md](modules.md) |
| La veille tourne-t-elle **en production** ? | l'historique d'une sentinelle **neuve** : sa première ligne ne peut avoir été écrite que par la boucle du serveur |
| Une sentinelle qui n'a pas bougé | ne prouve **rien** : sans changement, rien ne s'écrit — c'est le principe |
| Le déploiement est-il en place ? | `debug.ps1 install` — versions, serveur, puis le journal de l'installation |

## Quand rien ne répond

Dans l'ordre, sans en sauter :

1. **Le serveur est-il debout ?** `debug.ps1 server` — sinon, plus rien d'autre n'a de sens.
2. **Est-ce une installation en cours ?** Un verrou d'installation fait taire la veille et les recalculs, exprès.
3. **La console est-elle en pause ?** Voir la règle 1 : cliquer dans la fenêtre, **Échap**.
4. **Est-ce un refus de droits ?** Alors ce n'est pas un fait sur le poste : passer par `ask-vigie.ps1`.
