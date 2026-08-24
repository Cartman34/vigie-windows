# Documentation — Vigie

Deux points d'entrée, selon la langue :

- **[Documentation française](fr/README.md)** — utilisateur et développement
- **[English documentation](en/README.md)** — user and development

Les README du dépôt : [`README.md`](../README.md) (EN) · [`README.fr.md`](../README.fr.md) (FR).

---

## Comment cette documentation est organisée

| Dossier | Public | Répond à |
|---|---|---|
| `en/`, `fr/` | **utilisateur** | Comment je l'installe, m'en sers, le dépanne ? |
| `en/development/`, `fr/developpement/` | **développeur** | Comment c'est fait, comment j'ajoute une carte ? |
| `targeting/` | concepteur | Que **doit** faire le produit (par ID de fonctionnalité) ? |
| `implemented/` | concepteur | Que fait-il **réellement** aujourd'hui (mêmes ID) ? |
| `operating/SECURITY.md` | concepteur | La revue de sécurité interne, relue à chaque nouvelle action |

**Règle d'or : pas de doublon.** Chaque information vit dans UN seul endroit ; les autres y
renvoient. `targeting/` détient l'énoncé du besoin, `implemented/` l'état réel — on ne
réécrit jamais l'énoncé dans le second.

## Documents de travail internes

Ce sont la mémoire du projet. Ils ne s'adressent ni à l'utilisateur, ni au visiteur de
GitHub, et ils restent tels quels.

- [`DECISIONS-VALIDEES.md`](DECISIONS-VALIDEES.md) — chaque décision tranchée, numérotée `D01`…, avec son raisonnement et les pistes écartées
- [`REPRISE.md`](REPRISE.md) — où en est le projet, et le backlog
- [`conventions.md`](conventions.md), [`technologies.md`](technologies.md), [`DISCIPLINES.md`](DISCIPLINES.md), [`MIGRATION-APPS.md`](MIGRATION-APPS.md)
- [`maquettes-validees/`](maquettes-validees/) — les supports des décisions visuelles
- À la racine : [`SUIVI.md`](../SUIVI.md), [`CHANGELOG.md`](../CHANGELOG.md), [`PRISE-EN-MAIN.md`](../PRISE-EN-MAIN.md)
