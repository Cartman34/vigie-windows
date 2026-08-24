# Vigie — documentation

**Français** · [English](../en/README.md) · [Retour au README](../../README.fr.md)

Tout est à un clic d'ici, et chaque page est à un clic de n'importe quelle autre.

## Pour l'utilisateur

| Page | Répond à |
|---|---|
| [Installation](installation.md) | Comment l'installer ? Archive ou git ? Comment l'enlever ? |
| [Prise en main](prise-en-main.md) | C'est installé — et maintenant ? À quoi sert cette icône ? Comment lire une carte ? |
| [Ce que surveille Vigie](fonctionnalites.md) | Quelles cartes existent, ce que dit chaque champ, ce que fait chaque bouton |
| [Windows Update](windows-update.md) | Que change vraiment le verrou ? Comment installer les mises à jour ? |
| [Sécurité](securite.md) | Pourquoi administrateur ? Qu'est-ce qui est exposé ? Quel risque subsiste ? |
| [Configuration](configuration.md) | Changer le port, pointer l'outillage externe, surcharges propres à la machine |
| [Dépannage](depannage.md) | Rien ne s'ouvre, le serveur est à terre, où sont les journaux |

## Pour le développeur

| Page | Répond à |
|---|---|
| [Développement — commencer ici](developpement/README.md) | Arborescence, lancer depuis les sources, conventions |
| [Architecture](developpement/architecture.md) | Contract-first, les quatre apps, le chemin d'une requête |
| [Sondes et actions](developpement/sondes-et-actions.md) | Ajouter une carte ou un bouton sans toucher au contrat ni au front |

## Documents de travail internes

Ce sont la mémoire du projet, pas de la documentation d'usage. Ils restent tels quels.
Ils sont livrés avec le dépôt, **pas** avec l'archive de distribution : les liens
ci-dessous mènent donc à GitHub.

- [`docs/DECISIONS-VALIDEES.md`](https://github.com/Cartman34/vigie-windows/blob/main/docs/DECISIONS-VALIDEES.md) — chaque décision tranchée, numérotée `D01`…
- [`docs/REPRISE.md`](https://github.com/Cartman34/vigie-windows/blob/main/docs/REPRISE.md) — où en est le projet, et la suite
- [`SUIVI.md`](https://github.com/Cartman34/vigie-windows/blob/main/SUIVI.md) — journal courant
- [`CHANGELOG.md`](../../CHANGELOG.md) — historique des changements
- [`docs/targeting/features.md`](https://github.com/Cartman34/vigie-windows/blob/main/docs/targeting/features.md) — fonctionnalités cibles, par ID
- [`docs/implemented/status.md`](https://github.com/Cartman34/vigie-windows/blob/main/docs/implemented/status.md) — ce qui est réellement fait, par ID
- [`docs/conventions.md`](https://github.com/Cartman34/vigie-windows/blob/main/docs/conventions.md), [`docs/technologies.md`](https://github.com/Cartman34/vigie-windows/blob/main/docs/technologies.md)

## État

Version du produit **v0.1** (fichier [`VERSION`](../../VERSION) à la racine du dépôt ; le
préfixe `v` est ajouté à l'affichage). **Rien n'est publié** — aucune release, aucun
installeur, aucune garantie de compatibilité.
