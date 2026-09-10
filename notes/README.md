# `notes/` — ce qui est daté, et qui ne doit pas polluer la documentation

**Ce dossier garde le TEMPOREL.** Ce qui a une date, un contexte, une durée de vie :
extraits de preuves (journaux, mesures, sorties de commandes), morceaux d'échange à garder
en référence, constats bruts qu'on relira une fois et qu'on oubliera ensuite.

**La documentation, elle, n'a rien de temporel.** `doc/progress/decisions.md` porte les
arbitrages, `doc/progress/targeting/` ce que le produit doit faire,
`doc/progress/implemented/` ce qui est en place, `doc/en/agent-working/` la manière de
travailler. Aucun de ces fichiers ne raconte une journée : quand un constat daté s'y
glisse, il vieillit sur place et finit par mentir.

**Et `local/` ?** C'est le dossier ignoré par git : scripts jetables, extractions, fichiers
de travail, suivi personnel. Il ne survit pas à un clone, et c'est voulu — rien de ce qui
compte n'y vit.

| | | |
|---|---|---|
| `local/` | ignoré par git | jetable : scripts temporaires, extractions, suivi local |
| `notes/` | versionné | daté mais utile : preuves, mesures, extraits d'échange |
| `doc/` | versionné | intemporel : décisions, disciplines, mode d'emploi |
| `doc/progress/` | versionné | **l'état, pas une date** : ce qu'on vise, ce qui est fait, ce qui est ouvert |

**`doc/progress/` n'est pas intemporel, et ce n'est pas une entorse.** `targeting/` dit ce
qu'on vise aujourd'hui, `implemented/` ce qui est en place aujourd'hui, `subjects.md` ce qui
est ouvert aujourd'hui. Ces fichiers se **réécrivent** quand l'état change : ils ne gardent
pas la trace du passé, ils la remplacent. C'est exactement ce qui les distingue de `notes/`,
qui n'écrase jamais rien et dont chaque fichier reste vrai pour sa date.

La question à se poser n'est donc pas « est-ce daté ? » mais **« est-ce que cela s'écrase
ou est-ce que cela s'empile ? »** Un registre s'écrase, il va dans `progress/`. Une mesure
s'empile, elle va dans `notes/`.

**UNE DÉCISION SANS SA MESURE EST UNE OPINION.** Quand un arbitrage est tranché sur des
chiffres — un relevé, un journal, une sortie de commande — ces chiffres se déposent ici, et
la décision y renvoie. `decisions.md` porte le **quoi** et le **pourquoi** ; il n'a pas à
porter trois tableaux de mesures qui l'alourdiraient sans le rendre plus vrai. Sans cette
note, la mesure ne vit plus que dans un message de commit et dans un dossier temporaire
qu'on efface — c'est ce qui s'est passé pendant neuf jours, du 01/09 au 10/09, où ce
dossier n'a rien reçu alors que les décisions D115 à D118 ont toutes été prises sur des
mesures.

**Nommer un fichier par sa date et son sujet** : `2026-08-31-etat-lent.md`. On sait ainsi,
sans l'ouvrir, s'il a encore un intérêt.

*Ce fichier a été vidé par mégarde le 01/09 — un script qui l'ouvrait en écriture avant de
le lire — et la fabrication de l'archive s'est arrêtée dessus : `Get-Content -Raw` rend
`$null` sur un fichier vide. Les deux défauts sont corrigés ; celui-ci est réécrit.*
