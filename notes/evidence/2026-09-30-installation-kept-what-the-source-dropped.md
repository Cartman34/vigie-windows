# Deux app clientes sur le même compte, après un renommage — 30/09/2026

Relevé pris sur ce poste, dans l'heure qui a suivi le renommage du sujet **S06** (`b67ba38`). Il explique pourquoi une
copie d'installation qui n'efface jamais rien finit par faire tourner deux fois la même application.

## Ce qui s'est passé

Le dossier de l'app cliente est passé de `apps/tray/` à `apps/client/`, et son script de `tray.ps1` à `client.ps1`.
La mise à jour a été déployée à 09 h 24. Elle a bien posé `apps/client/` — et elle a **gardé** `apps/tray/` :
`Copy-InstallFrom` ajoutait et écrasait, sans jamais supprimer ce que la source n'avait plus.

La tâche planifiée du compte, elle, nommait toujours l'ancien script. Ce n'était pas détecté comme un défaut : le
contrôle demandait seulement que le fichier **existe**, et il existait.

| Moment | Ce qui a été mesuré |
|---|---|
| 09:24:45 | L'app cliente reçoit l'ordre `stop` et se termine (`tray_20260930.log`) |
| 09:25:23 | Une app cliente **neuve** démarre depuis `apps/client/client.ps1` (PID 16868) |
| 09:26:22 | Une app cliente **ancienne** démarre depuis `apps/tray/tray.ps1` (PID 54004), lancée par la tâche du compte |
| 09:27:15 | Deux battements de cœur côte à côte : `client.alive` et `tray.alive`, à six secondes d'écart |

Deux icônes dans la zone de notification, deux protocoles `vigie://` déclarés, deux guetteurs d'adresse réseau, et un
compte que la carte « Processus de Vigie » voyait comme sain — puisqu'un battement, elle en avait un.

## Ce qui a été corrigé

1. **L'installation supprime ce que la source n'a plus**, à la racine et dans `apps/`. `var/` est la seule chose
   gardée : c'est la donnée, pas le code. Rien hors du dossier d'installation n'est touché.
2. **Une tâche qui lance une autre application que celle installée est un défaut structurel.** Exister ne suffit plus :
   le chemin doit être celui de l'app cliente de l'installation en cours. La réparation des tâches la réécrit alors
   d'elle-même, au démarrage de l'app serveur — ce qu'elle a fait sur ce poste, vérifié à 09 h 36.

## Ce qu'il faut en retenir

Une mise à jour exécute **l'installateur déjà posé**, pas celui qu'elle apporte. Le correctif d'une installation ne
s'applique donc qu'au déploiement **suivant** : le premier pose le code corrigé, le second s'en sert. C'est vrai de
tout ce qui touche à la pose elle-même, et c'est à prévoir dans le plan, pas à découvrir après coup.
