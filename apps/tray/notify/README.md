# Les outils de notification

Un fichier par outil. La conception, elle, vit dans
[`doc/progress/targeting/notifications.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/progress/targeting/notifications.md) : cette page ne dit que
ce qui est là.

`Show-VigieNotification` (`common.ps1`) les parcourt **dans l'ordre de leur nom** et s'arrête au premier qui affiche.
Chacun reçoit le même couple :

- `-Notification` : `Subject`, `Body`, `State` (`ok` / `warn` / `error`), `Duration` en millisecondes ;
- `-Context` : `TrayRoot`, `Aumid`, `Icon` — l'icône de la barre système, pour qui en a besoin.

Chacun rend `$true` s'il a affiché, `$false` s'il décline. **Il ne lève jamais** : un outil qui échoue laisse la place
au suivant, il n'interrompt rien.

| Fichier | Outil |
|---------|-------|
| `20-winrt-com.ps1` | `Windows.UI.Notifications`, ouverte par COM dans le processus même |
| `40-winrt-host.ps1` | la même API, par un `powershell.exe` le temps d'un appel |
| `90-balloon.ps1` | la bulle de l'icône de barre système — **toujours disponible**, c'est sa raison d'être |

Ajouter un outil, c'est déposer un fichier ici, avec le rang qu'on lui donne dans son nom. Rien d'autre à toucher.
