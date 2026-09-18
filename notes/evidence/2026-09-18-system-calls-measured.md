# Les appels système du lot du 18/09, mesurés — 18/09/2026

## Pourquoi

Règle de `doc/en/agent-working/disciplines.md`, section « Wrapping system calls » : l'appel optimisé qui donne
l'information nécessaire, mesuré en vitesse et en accord avec l'ancien avant d'être livré. Mesures prises le 18/09
depuis la session de fhaza, sur 570 à 575 processus ; la seconde passe compte, la première compile les classes.

## Remplacés

| Besoin | Avant | Durée | Après | Durée | Accord |
|---|---|---|---|---|---|
| E/S cumulées par processus (carte Jeu, deux relevés) | `Win32_Process` | 548 ms | `NtQuerySystemInformation` (`Get-ProcessTransferBytes`) | 14 ms | identique sur les 575 processus |
| Utilisation des moteurs GPU, 867 instances | `Get-Counter` | 6 257 ms | PDH direct (`VigiePdh`), relevés calés sur l'attente de la carte | 350 ms pour ouvrir et lire, 3 ms le second relevé | mêmes 867 instances ; sommes voisines, prises à des instants différents |
| Mémoire GPU par processus, `Local Usage` | `Get-Counter` | 1 016 ms | PDH direct | compris ci-dessus | 2 230 Mo contre 2 209 Mo, instants différents |
| Mémoire de l'adaptateur | `Get-Counter` | 1 013 ms | PDH direct | compris ci-dessus | 1 991 Mo des deux côtés |
| Parent d'un processus (résident Jeu) | `Win32_Process` | 465 ms | instantané Toolhelp (`Get-ParentProcessId`) | 15 ms | même parent |
| Démarrage de Windows | `Win32_OperatingSystem` | 573 ms | `Environment.TickCount64` (`Get-BootTime`) | 0 ms | 17/09 13:58:54 contre 13:58:55 ; le journal (Kernel-General 12) dit 13:58:55 |
| Descendants de l'app serveur | — | — | instantané Toolhelp (`Get-ProcessDescendants`) | 15 ms, 105 ms avec les heures de départ | — |
| Ports éphémères occupés, par processus | — | — | `GetExtendedTcpTable` classe 5, `GetExtendedUdpTable` classe 1 | 20 ms TCP, 1 ms UDP | — |
| Plage des ports éphémères | — | — | `netsh int ipv4 show dynamicport` | 170 à 220 ms, gardée une heure | — |
| Journal Système, niveaux 1 à 3 sur 24 h | — | — | `Get-WinEvent` avec filtre | 80 ms pour 43 événements | — |

La sonde Jeu est passée de 8,7 s à 1,8 s, dont 0,9 s d'attente voulue entre ses deux relevés.

## Gardés

| Appel | Durée | Raison |
|---|---|---|
| `Win32_OperatingSystem`, nom de l'édition (`os.probe.ps1`) | 573 ms, une fois l'heure | le registre donne « Windows 10 Pro » sur Windows 11 : perte d'exactitude |
| `SoftwareLicensingProduct`, activation (`os.probe.ps1`) | 1 107 ms, une fois l'heure | aucun remplaçant éprouvé ici |
| `Win32_Process` avec `CommandLine LIKE`, copies d'un résident | 490 ms, carte Débogage éteinte par défaut | seule source de la ligne de commande sans lire la mémoire des processus |
| `Win32_VideoController`, `Win32_LogicalDisk` | 30 ms et 11 ms | déjà rapides |
