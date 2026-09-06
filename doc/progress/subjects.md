# Sujets ouverts — `SXX`

Un sujet ouvert porte un **numéro court**, `S01`, `S02`… C'est un moyen de le désigner en une conversation, sans
réciter un identifiant de fonctionnalité ni redire de quoi il s'agit. **Il n'y a rien à faire ici** : ce fichier ne
décide de rien, il ne fait que **nommer** ce qui est décrit ailleurs et pointer vers l'endroit qui fait foi.

**Un numéro ne se réutilise jamais.** Un sujet réglé garde le sien, marqué clos avec sa date : une phrase écrite il y a
trois mois doit encore désigner la même chose aujourd'hui. Réattribuer `S03` rendrait faux tout ce qui a été dit avant.

**Un sujet n'est pas une tâche.** C'est une chose qui reste ouverte et sur laquelle on revient — un manque assumé, une
preuve qui n'a pas eu lieu, une dette. Ce qui se règle dans la journée n'a pas besoin d'un numéro.

## Ouverts

| N° | Sujet | Où c'est décrit | Pourquoi c'est ouvert |
|----|-------|-----------------|-----------------------|
| **S01** | Confiance de la chaîne de mise à jour | `targeting/features.md` → `CORE-UPDATE-TRUST` | Rien ne vérifie que ce qui s'installe est bien ce qui a été publié. **Décidé le 05/09 : dans la cible, pas maintenant** — mais la chaîne d'aujourd'hui ne doit rien faire qui empêche une version future de vérifier. |
| **S02** | Les mesures par utilisateur, invisibles depuis la session 0 | `targeting/multi-account-server.md` → C4 | WSL et les gestionnaires de paquets répondent pour le compte de service, pas pour le compte qui regarde. |
| **S03** | La désinstallation n'a jamais été éprouvée en vrai | `targeting/uninstall.md` | Elle est écrite et relue, jamais exécutée : **c'est un geste de l'utilisateur, jamais le mien**. Tant qu'elle n'a pas eu lieu, on sait qu'elle est cohérente, pas qu'elle marche. |
| **S04** | L'audit Windows Update ne remonte pas dans l'interface | `implemented/status.md` → `WU-AUDIT` | Le rapport s'écrit sur disque et personne ne le voit depuis Vigie. |
| **S05** | Les actions longues ne suivent pas le contrat | `implemented/status.md` | Le suivi passe par les marqueurs d'occupation et `/operations`, pas par le `202 + jobId` que décrit le contrat. |
| **S06** | « tray » dans les identifiants | **D108** | Le vocabulaire affiché est réglé ; les dossiers, fichiers et clés gardent leur ancien nom. Par étapes, en touchant chaque zone quand on y travaille déjà. |
| **S07** | Le français dans le code | `dev/check-naming.ps1` | Trois cliquets qui ne peuvent que descendre : identifiants français, noms de fichiers français, lignes de commentaire françaises (**D115**). Ils baissent quand on passe à côté, jamais en campagne dédiée. |
| **S08** | Deux fichiers Python subsistent | **D41** | PHP est l'outil par défaut ; Python n'est toléré qu'argumenté et délimité. Cliquet posé à 2 dans `check-naming`. |
| **S09** | Preuves qui n'ont jamais eu lieu | — | L'installation sur un **second ordinateur** depuis la v1.0.0, l'alerte de **décharge batterie** pendant une partie, et l'export **imprimé pour de vrai**. Trois choses écrites que rien n'a encore confrontées au réel. |

## Clos

*(aucun pour l'instant — un sujet réglé descend ici avec sa date et le commit qui l'a clos)*
