# Désinstallation — ce qui doit disparaître, et comment

Vigie doit savoir s'en aller. ID concerné : **CORE-UNINSTALL**. L'installation, elle, vit dans
[`install-update.md`](install-update.md).

**Le point d'entrée est `uninstall.cmd`**, livré à côté de `setup.cmd`. Un script, pas un bouton : il doit fonctionner
quand l'app serveur est morte, quand l'installation est à moitié défaite, ou quand plus rien ne répond — c'est-à-dire
précisément les jours où on désinstalle.

---

## Ce qui est dit AVANT l'élévation

La désinstallation exige les droits administrateur. La fenêtre qui précède la demande d'élévation — la même mécanique
que l'installation — annonce **ce qui va être supprimé**, et laisse **confirmer ou quitter**. Elle nomme en particulier
la chose que personne n'attend :

> **Les données de Vigie de TOUS les comptes de cette machine seront supprimées** — réglages, historiques, journaux.

Cela suppose de les **inventorier** : non pas les comptes actifs, ni même les comptes qui existent encore, mais **tous
ceux qui ont eu des données un jour**. Le disque fait foi — un dossier `Sowapps\Vigie` subsiste dans un profil dont le
compte a été supprimé, et il doit partir aussi.

---

## Ce qui doit disparaître

| # | Quoi | Où | Pourquoi ça ne peut pas rester |
|---|---|---|---|
| 1 | **Le verrou sur Windows Update** | ACL des dossiers de tâches WU (refus pour SYSTEM) | **Le point dangereux.** Partir en le laissant rend la machine durablement bloquée, sans plus rien pour l'expliquer ni le lever. Il se retire AVANT tout le reste : tant que Vigie est là, elle peut encore le faire proprement. |
| 2 | **La tâche serveur** `Vigie - Serveur` | Planificateur de tâches | Elle relancerait l'app serveur au prochain démarrage, sur un dossier disparu. |
| 3 | **Les tâches d'app cliente** `Vigie` et `Vigie - <compte>` | Planificateur de tâches | Idem, à chaque ouverture de session. |
| 4 | **Le compte local `VigieService`** | Comptes locaux Windows | Un compte de service sans service est une porte de plus, et son mot de passe reste dans le coffre de Windows. |
| 5 | **La ligne qui masque ce compte** | `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList` | Posée par l'installation pour que le compte n'apparaisse pas à l'écran d'accueil. Elle survivrait au compte lui-même. |
| 6 | **Le profil du compte de service** | `C:\Users\VigieService` | Supprimer un compte local ne supprime pas son profil : le clone du dépôt, le cache et les secrets y restent. |
| 7 | **Les déclarations `safe.directory`** | Configuration git **de la machine** | Posées pour que le compte de service puisse lire le dépôt. Elles désignent ensuite des chemins qui n'ont plus de raison d'être. |
| 8 | **Le dossier d'installation partagé** | Le chemin choisi à l'installation | Avec sa configuration de machine. Il se retire en dernier : il contient ce qui exécute la désinstallation. |
| 9 | **Les données de chaque compte** | `%LOCALAPPDATA%\Sowapps\Vigie` dans **tous** les profils | Annoncées avant l'élévation (ci-dessus). |

**Ce qui ne se supprime PAS : les prérequis.** PowerShell 7 et le module Pode ont pu être posés par l'installation,
mais on ignore qui d'autre s'en sert sur cette machine. On ne retire jamais un outil général.

---

## Les règles

- **On dit ce qu'on fait, et ce qu'on n'a pas pu faire.** Une désinstallation qui échoue à mi-chemin est le pire des
  états : elle nomme chaque élément resté en place, et comment le retirer à la main.
- **Un élément déjà absent n'est pas une erreur.** Désinstaller deux fois de suite doit aboutir, comme installer deux
  fois de suite (idempotence).
- **L'ordre compte** : le verrou de Windows Update d'abord, le dossier d'installation en dernier.
