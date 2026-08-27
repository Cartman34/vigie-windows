# Vigie — documentation

**Français** · [English](../en/README.md) · [Retour au README](../../README.fr.md)

Tout est à un clic d'ici, et chaque page est à un clic de n'importe quelle autre.

## Pour l'utilisateur

| Page | Répond à |
|---|---|
| [Installation](install.md) | Comment l'installer ? Archive ou git ? Comment l'enlever ? |
| [Premiers pas](getting-started.md) | C'est installé — et maintenant ? À quoi sert cette icône ? Comment lire une carte ? |
| [Ce que surveille Vigie](features.md) | Quelles cartes existent, ce que dit chaque champ, ce que fait chaque bouton |
| [Windows Update](windows-update.md) | Que change vraiment le verrou ? Comment installer les mises à jour ? |
| [Sécurité](security.md) | Pourquoi administrateur ? Qu'est-ce qui est exposé ? Quel risque subsiste ? |
| [Configuration](configuration.md) | Changer le port, pointer l'outillage externe, surcharges propres à la machine |
| [Dépannage](troubleshooting.md) | Rien ne s'ouvre, le serveur est à terre, où sont les journaux |

## Pour le développeur

| Page | Répond à |
|---|---|
| [Développement — commencer ici](../en/developing/README.md) | Arborescence, lancer depuis les sources, conventions |
| [Architecture](../en/developing/architecture.md) | Contract-first, les quatre apps, le chemin d'une requête |
| [Sondes et actions](../en/developing/probes-and-actions.md) | Ajouter une carte ou un bouton sans toucher au contrat ni au front |

## Documents de travail internes

Ce sont la mémoire du projet, pas de la documentation d'usage. Ils restent tels quels.
Ils sont livrés avec le dépôt, **pas** avec l'archive de distribution : les liens
ci-dessous mènent donc à GitHub.

- [`doc/progress/decisions.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/progress/decisions.md) — chaque décision tranchée, numérotée `D01`…
- [`doc/en/agent-working/briefing.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/en/agent-working/briefing.md) — où en est le projet, et la suite
- [`SUIVI.md`](https://github.com/Cartman34/vigie-windows/blob/main/SUIVI.md) — journal courant
- [`CHANGELOG.md`](../../CHANGELOG.md) — historique des changements
- [`doc/progress/targeting/features.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/progress/targeting/features.md) — fonctionnalités cibles, par ID
- [`doc/progress/implemented/status.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/progress/implemented/status.md) — ce qui est réellement fait, par ID
- [`doc/en/developing/conventions.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/en/developing/conventions.md), [`doc/en/developing/technologies.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/en/developing/technologies.md)

## État

Version du produit **v0.1** (fichier [`VERSION`](../../VERSION) à la racine du dépôt ; le
préfixe `v` est ajouté à l'affichage). **Rien n'est publié** — aucune release, aucun
installeur, aucune garantie de compatibilité.
