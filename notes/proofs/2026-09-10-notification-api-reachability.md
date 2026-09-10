# 2026-09-10 — Notifications : quelle API est réellement atteignable

**Preuve derrière `targeting/notifications.md` et S13.** L'utilisateur demandait une vraie
icône dans les bulles, puis a contesté ma première conclusion — « es-tu sûr qu'il n'y a pas
une autre API ? » — et il avait raison : j'avais conclu à partir du seul chemin qui avait
marché. Voici ce qui a été essayé, et ce que chaque essai a répondu.

## Les essais, dans l'ordre

| Voie | Résultat |
|---|---|
| `NotifyIcon.ShowBalloonTip` | Fonctionne. Le glyphe ne peut valoir que `None`, `Info`, `Warning`, `Error` — vérifié par `[Enum]::GetNames`. Aucune icône à nous. |
| `Windows.UI.Notifications` depuis **PowerShell 7** | **Échec** : « Unable to find type ». La projection WinRT a été retirée à partir de .NET 5 ; ni `WinRT.Runtime.dll` ni `Microsoft.Windows.SDK.NET.dll` dans `$PSHOME` (PS 7.6.5). |
| La même API depuis **Windows PowerShell 5.1** | **Fonctionne**, sans rien installer. |
| COM avec `InterfaceIsIInspectable` / `UnmanagedType.HString` | **Échec** : « Marshalling as IInspectable is not supported in the .NET runtime. » |
| COM en parcourant les tables de méthodes **à la main** | **Fonctionne**, dans le processus, sans bibliothèque livrée ni processus fils. |
| `AppNotificationManager` (Windows App SDK) | Non essayé. Le runtime est présent ici — 19 paquets amenés par d'autres logiciels — mais il faut l'amorceur, et rien ne garantit sa présence ailleurs. |
| BurntToast | Absent de la machine. Enveloppe `Windows.UI.Notifications`, donc n'ouvre aucune porte nouvelle. |

## Le détail qui a débloqué la voie COM

Chaque interface WinRT commence par les trois entrées d'`IUnknown` **plus** les trois
d'`IInspectable` : la première méthode utile est donc au **rang six**. C'est toute
l'astuce, et elle est écrite dans `apps/tray/notify/20-winrt-com.ps1` plutôt que recomptée.

Vérifié sans rien afficher : fabrique obtenue, notificateur obtenu, document XML chargé,
notification construite — en s'arrêtant avant `Show()`.

## La qualité des icônes

Les `.ico` livrés portent six tailles, **jusqu'à 256** — ils ne sont pas en cause. C'est le
rendu des notifications qui pioche une petite image dans un `.ico` et l'agrandit ; le
contour sort en escalier, vu à l'écran par l'utilisateur. Le PNG 256 était **déjà dans
chaque `.ico`**, en PNG compressé : recopié octet pour octet, sans réencoder.

## Contrainte de la machine, à ne pas oublier

`Get-ExecutionPolicy -List` donne `LocalMachine = AllSigned`, sans stratégie de groupe. Un
`powershell.exe -File <script non signé>` est donc **refusé** ici. C'est pourquoi le rang 40
passe une **commande** et jamais un fichier : une stratégie d'exécution ne s'applique
qu'aux fichiers de script.

## Ce qui n'a pas été vérifié

- Le rang 20 n'a **jamais affiché** de notification depuis l'app cliente réelle : il a été
  éprouvé jusqu'à l'objet prêt, et les bulles vues à l'écran venaient du rang 40.
- Le comportement quand l'identité `Sowapps.Vigie` n'est pas déclarée dans le registre :
  `CreateToastNotifierWithId` devrait échouer et faire descendre d'un rang, jamais essayé.
