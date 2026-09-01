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
| `doc/` | versionné | intemporel : décisions, cible, existant, disciplines |

**Nommer un fichier par sa date et son sujet** : `2026-08-31-etat-lent.md`. On sait ainsi,
sans l'ouvrir, s'il a encore un intérêt.

*Ce fichier a été vidé par mégarde le 01/09 — un script qui l'ouvrait en écriture avant de
le lire — et la fabrication de l'archive s'est arrêtée dessus : `Get-Content -Raw` rend
`$null` sur un fichier vide. Les deux défauts sont corrigés ; celui-ci est réécrit.*
