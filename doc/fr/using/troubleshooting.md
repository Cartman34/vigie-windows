# Dépannage

[Sommaire](../README.md) · [English](../../en/using/troubleshooting.md)

---

## Les premiers réflexes

| Question | Réponse |
|---|---|
| Le serveur est-il vivant ? | ouvrez <http://127.0.0.1:47600/api/v1/health> — aucune authentification requise |
| Le tray est-il vivant ? | `pwsh -File .\scripts\tray.ps1 -Status` |
| Où sont les journaux ? | menu du tray → **Ouvrir les journaux** — c'est le plus sûr, le dossier dépend de l'installation |

## Situations courantes

### La page affiche des données de maquette (liseré orange)

Le liseré sous l'en-tête est orange : la page n'a pas pu joindre l'API et s'est repliée sur
le jeu d'exemple `apps/frontend-web/mock/state.json`. Le serveur ne tourne pas, ou pas sur
le port attendu. Relancez-le depuis le menu du tray, ou par `scripts\run.ps1`.

### Rien ne se lance à l'ouverture de session

La tâche planifiée n'est pas enregistrée, ou pointe sur un dossier qui a bougé. Relancez :

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\install-autostart.ps1
```

C'est idempotent, et cela ré-enregistre la tâche sur le dossier courant. Si vous avez
déplacé ou renommé le dossier de Vigie, c'est le remède.

### L'icône est rouge

Le serveur est arrêté ou en erreur. Menu du tray → **Redémarrer le serveur**, puis
**Ouvrir les journaux** et lisez `pode-error_*.log` et le `start_*.log` le plus récent.

### L'icône a disparu mais Vigie tourne encore

Le tray tourne élevé : depuis une session normale, on ne peut pas le signaler directement.
Passez par le pilote dédié, qui dépose un ordre que le tray va lire :

```powershell
pwsh -File .\scripts\tray.ps1 -Status     # vivant ? depuis quand ? affichant quoi ?
pwsh -File .\scripts\tray.ps1 -Restart    # le relancer
pwsh -File .\scripts\tray.ps1 -Stop       # l'arrêter proprement, en libérant l'icône
```

Codes de retour : `0` succès, `1` tray absent, `2` ordre non pris en compte à temps (15 s
par défaut, `-TimeoutSec` pour changer). En cas de dépassement, le tray est peut-être
figé : regardez `apps\tray\var\log\` et `apps\tray\var\run\`.

Pour le relancer : `Start-ScheduledTask -TaskName Vigie`, ou `scripts\start-vigie.vbs`.

### Une carte tourne indéfiniment

Une tâche de fond peut mourir sans rien écrire (machine mise en veille, processus tué). Les
cartes de gestionnaires de paquets abandonnent au bout de **45 minutes** et cessent
d'afficher « en cours ». Pour les autres, redémarrez le serveur depuis le menu du tray.

### « Aucun dossier d'outillage n'est configuré »

Ce message ne concerne **plus aucune fonction** : le verrouillage de Windows Update, son
audit et les bascules VBS / intégrité mémoire sont natifs. Seule *Ouvrir le dossier* peut
encore le rendre, et uniquement si le dossier disparaît entre l'affichage de la carte et le
clic — sans chemin configuré, le bouton n'est pas proposé.
Voir [Configuration](../operating/configuration.md#outillage-externe).

### « Le serveur de Vigie n'est pas administrateur »

Poser ou lever le verrou modifie les permissions de dossiers système ; basculer VBS ou
l'intégrité mémoire écrit dans une clé de registre protégée. Sans élévation, la manœuvre
échouerait à moitié, en silence. Vigie refuse donc **avant** d'agir et ne touche à rien.
Relancez Vigie en administrateur (menu du tray → *Redémarrer le serveur*, l'invite UAC
s'affichera), puis recliquez.

### La bascule VBS ou intégrité mémoire « ne change rien »

C'est normal et c'est dit : ces réglages sont lus par Windows **au démarrage**. La demande
est écrite dans le registre, la carte affiche *En attente de redémarrage* et propose
*Redémarrer Windows*. L'état affiché au-dessus reste celui qui tourne jusque-là.

Si la valeur ne s'applique toujours pas **après** un redémarrage, elle est imposée par
l'UEFI ou par une stratégie d'entreprise : passez par *Sécurité Windows → Sécurité des
appareils → Isolation du noyau*, ou voyez votre service informatique. Vigie ne peut pas
passer outre, et le dit plutôt que de prétendre avoir réussi.

### « Verrouiller maintenant » dit que le verrou ACL n'a pas pu être posé

Windows protège certains de ces dossiers de tâches. Vigie le dit exactement, au lieu de
prétendre à un succès, et pointe le journal qu'elle a écrit. Les mises à jour automatiques
restent coupées — c'est la part qui compte le plus — mais le champ *Verrou ACL* restera
orange.

### La fenêtre dédiée ne s'ouvre pas

Le mode `--app` n'existe que sur les navigateurs Chromium. Sans Edge ni Chrome, utilisez
**Ouvrir dans le navigateur** depuis le menu du tray.

### PowerShell refuse d'exécuter les scripts

Utilisez les lanceurs `.cmd` (`scripts\run.cmd`, `scripts\install-autostart.cmd`), qui
passent `-ExecutionPolicy Bypass`. Si vous avez installé depuis une archive téléchargée,
débloquez les fichiers une fois :

```powershell
Get-ChildItem -Recurse | Unblock-File
```

### « pwsh introuvable »

PowerShell 7 manque. `scripts\install.ps1` l'installe via winget, puis demande de le
relancer. Sans winget : <https://aka.ms/powershell-release>.

### Le port 47600 est déjà pris

Choisissez un autre port dans `apps/backend-pode/config/config.local.psd1` — voir
[Configuration](../operating/configuration.md). Tout en dérive, y compris le raccourci bureau : relancez
donc `install-autostart.ps1` ensuite.

---

## Les fichiers de journal

Le dossier dépend de l'installation : **Vigie installée** écrit dans votre profil,
`%LOCALAPPDATA%\Sowapps\Vigie\var\log\` ; **lancée depuis un clone git**, elle écrit sur place, sous le `var/`
de chaque app. Le menu du tray → *Ouvrir les journaux* ouvre le bon dossier sans avoir à le chercher.

| Fichier | Écrit par |
|---|---|
| `install_*.log` | `scripts\install.ps1` (transcript complet) |
| `run_*.log` | `scripts\run.ps1` — ce qu'il a décidé, et pourquoi |
| `start_*.log` | le serveur lui-même |
| `pode-error_*.log`, `pode-request_*.log` | le runtime Pode |
| `action-*.log` | certaines actions, quand elles journalisent |
| `tray_*.log` | l'app de la barre système |

Les scripts élevés écrivent leur sortie dans un fichier que le processus appelant relit : le
compte rendu d'une exécution élevée n'est jamais perdu.

## Toujours bloqué

Ouvrez un ticket sur <https://github.com/Cartman34/vigie-windows/issues>, avec l'extrait de
journal pertinent, vos versions de Windows et de PowerShell, et l'information de savoir si
le serveur était élevé. Vigie est en **v0.1 et n'est pas publiée** : les aspérités sont
attendues.
