# Une question de port qui prend 26 secondes — 14/09/2026

## Ce qui a été observé

La mise à jour de Vigie du 14/09 à 19 h 34 a pris 225 s, contre 98 s la veille. Les journaux horodatés du compte de
service (`install_20260914.log`, comparé à `install_20260913.log`) placent l'écart sur les lignes qui suivent une
question « quelqu'un écoute-t-il sur le port 47600 ? » :

| Étape | 13/09 | 14/09 |
|---|---|---|
| affichage de l'état du service, jusqu'à « Serveur en ligne » (deux fois) | 4 s et 2 s | 25 s et 23 s |
| enregistrement de la tâche serveur, jusqu'à « fait » | 4 s | 26 s |
| de l'archive prête à l'installation élevée (arrêt, port libre, sauvegarde, copie) | 20 s | 65 s |

## Les mesures

Trois passes, le 14/09, depuis la session de fhaza :

| Appel | Durée | Donne le processus |
|---|---|---|
| `Get-NetTCPConnection -LocalPort 47600 -State Listen` | 26,1 à 26,4 s | oui |
| le même, sur un port où personne n'écoute | 25,8 à 26,9 s | — |
| `GetExtendedTcpTable`, classe « écouteurs seulement » | 0,000 à 0,002 s | oui |
| `IPGlobalProperties.GetActiveTcpListeners()` | 0,001 à 0,010 s | non |
| `netstat -ano -p TCP`, filtré | 0,02 à 0,11 s | oui |
| compilation de la classe native, une fois par processus | 0,28 s | — |

Le service qui écoute sur le port 53 (le proxy DNS local), retrouvé à partir de son processus :

| Appel | Durée |
|---|---|
| `Get-CimInstance Win32_Service -Filter "ProcessId=…"` | 0,95 à 1,13 s |
| `tasklist /svc /fi "PID eq …"` | 0,26 à 0,61 s |
| `EnumServicesStatusEx`, tous les services actifs en un appel | environ 0,005 s pour la détection entière |

Après remplacement, vérifié contre `netstat` : les 26 ports TCP en écoute et tous les ports UDP qu'il liste sont vus.

L'ordinateur tenait **10 775** connexions TCP, dont **10 426** à l'état `Bound`, toutes au même processus : `dllhost`
(PID 43732), lancé le 13/09 à 6 h 23 sous le compte de fhaza, hôte COM de `C:\Program Files\WSL\wsldevicehost.dll`
(AppID `{17696EAC-9568-4CF5-BB8C-82515AAD6C09}`, classes `WslDeviceHost_Net`, `WslDeviceHost_VirtioFs`).

## Ce que cela montre

- `Get-NetTCPConnection` énumère toutes les connexions de l'ordinateur par WMI avant de filtrer : sa durée suit le
  nombre de connexions ouvertes, pas la question posée.
- Vigie ne tient pas ces connexions : l'hôte réseau de WSL, oui.
- L'appel natif qui ne demande que les écouteurs répond plus de dix mille fois plus vite, avec le processus.

## Ce qui n'a PAS été vérifié

- Pourquoi l'hôte réseau de WSL garde ces sockets, et si `wsl --shutdown` les libère : rien n'a été arrêté.
- Le détail de l'étape « arrêt, port libre, sauvegarde, copie » : elle n'a pas d'horodatage intérieur.
- La durée de `Get-NetUDPEndpoint`, remplacé par le même principe sans mesure propre.
- Le nouveau code n'a pas encore tourné dans l'app serveur ni pendant une mise à jour : il attend le prochain
  déploiement.
