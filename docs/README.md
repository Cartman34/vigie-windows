# Documentation — Vigie

Deux points d'entrée pour **utiliser** Vigie, selon la langue :

- **[Documentation française](fr/README.md)**
- **[English documentation](en/README.md)**

Les README du dépôt : [`README.md`](../README.md) (EN) · [`README.fr.md`](../README.fr.md) (FR).

---

## Comment cette documentation est organisée

| Dossier | Public | Répond à |
|---|---|---|
| `fr/`, `en/` | **utilisateur** | Comment je l'installe, m'en sers, le dépanne ? |
| `en/developing/` | **développeur** | Comment c'est fait, comment j'ajoute une carte ? |
| `en/agent-working/` | **l'agent** | Ce qu'il faut savoir avant de toucher au projet, et les règles à tenir |
| `progress/` | **conception** | Ce qu'on vise, ce qui est fait, ce qu'on a décidé |
| `archives/` | trace | Ce qui est révolu : historiques, migration terminée, maquettes validées |

Trois choix expliquent cette forme :

- **Les noms de fichiers sont techniques, donc en anglais** — même pour un contenu
  français. `fr/install.md` et `en/install.md` portent le même nom : on retrouve
  l'équivalent sans traduire. Le *contenu*, lui, est dans la langue du dossier.
- **La doc de développement n'existe qu'en anglais**, et vit donc hors des dossiers de
  langue. Rien n'oblige `fr/` et `en/` à contenir les mêmes fichiers.
- **La file de travail n'est jamais commitée.** L'état à l'instant et ce qui reste à
  faire vivent dans `local/`, ignoré par git : cela change à chaque session et
  n'appartient qu'à une machine.

**Règle d'or : pas de doublon.** Chaque information vit dans UN seul endroit ; les autres
y renvoient. `progress/targeting/` détient l'énoncé du besoin, `progress/implemented/`
l'état réel — on ne réécrit jamais l'énoncé dans le second.

## Ce qui ne part pas dans l'archive publiée

`progress/`, `archives/`, `en/agent-working/`, `en/developing/security-review.md` et ce
fichier même : ce sont des documents de projet, sans objet pour qui installe Vigie. Le
script de fabrication les écarte nommément, chacun avec sa raison
([`scripts/build-release.ps1`](../scripts/build-release.ps1)).
