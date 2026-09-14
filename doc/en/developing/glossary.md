# Glossary — the project's words

One word per notion, and the same everywhere: code, documentation, interface. When a word is missing, it is added
**here first**, then used. A synonym that settles in ends up meaning something else.

Each word is given in English, as the code and this documentation use it, followed by the French word the interface and
the French documentation use.

## The two applications

| word | what it means |
|---|---|
| **server app** (*app serveur*) | `apps/backend-pode`: PowerShell + Pode, listens on 127.0.0.1:47600, runs **elevated** under the service account, without a session. It measures, decides rights, runs actions. |
| **client app** (*app cliente*) | `apps/tray`: the icon in the notification area, one per open account. It starts the server if needed, opens the panel and carries Windows notifications. |
| **panel** (*panneau*) | `apps/frontend-web`: the page served by the server app, the one where cards are read. |
| **Atelier** | `apps/atelier`: a **development** tool (PHP, port 47610, never elevated). It is not part of what ships. |

*"tray" is no longer written in displayed text: it is **app cliente**. The word survives in paths and identifiers
(`apps/tray/`), which are renamed area by area.*

## What Vigie shows

| word | what it means |
|---|---|
| **card** (*carte*) | a block of the screen: a title, rows, buttons. It carries an identifier (`net`, `deployment`). |
| **group** (*groupe*) | a card's family, shown above its title: Comptes, Système, Réseau… |
| **field** (*champ*) | a row of a card: a label, a value, a status, a help text, sometimes a button. |
| **status** (*statut*) | `ok` · `warn` · `error` · `neutral`. A `warn` or an `error` **always carries** the gesture that fixes it (D66). |
| **action** | what a button triggers. It declares its rights (`@droits`) and where it runs (`@execution`). |

## What measures

| word | what it means |
|---|---|
| **module** | a folder of `probes/`: its probes, its declaration (`module.psd1`), its settings, its notifications, its sentinels. It is the unit that is enabled or disabled. |
| **probe** (*sonde*) | `<name>.probe.ps1`: it measures and **returns one or more cards**. Read only, never a side effect. |
| **sentinel** (*sentinelle*) | `<key>.watch.ps1`: a **cheap** read returning **a comparable value**. The server app runs it permanently, even without a session; when the value **changes**, it emits an **event** that recomputes the declared cards. It never computes a card itself. |
| **event** (*événement*) | what a sentinel emits when its value changes. It triggers a targeted recompute — it is not displayed. |
| **measurement** (*mesure*) | a **named series** (`disk.free`, `game.gpu`, `watch.internet`) — not a unit. It has its identifier, its folder in `var/history/`, its minimum cadence, its tolerance and its retention. The unit (`Go`, `%`, `ms`) is only one of its attributes. |
| **tolerance** (*tolérance*) | how far a measurement must turn for it to be a real reversal. Below that it is noise, and the intermediate point is erased. |
| **sentinel history** (*historique d'une sentinelle*) | the sequence of a sentinel's states, one line per **change** (`watch.<key>`), with the previous state and the recomputed cards. The watch memory says where things stand; the history says since when, and how many times. |
| **notification** | the Windows toast. It is born from a **card field switching**, not from a sentinel event (D54). |
| **resident** (*résident*) | a component the server app **arms at start** and that lives as long as it does: a subscription, a listener, a state held in memory. It re-arms it if it dies, and none outlives it. Design: `../../progress/targeting/residents.md`. |
| **worker** | `workers/<name>.worker.ps1`: the work of an **asynchronous operation** — installing updates, querying package managers. `Start-Operation` launches it under a watcher, the action answers at once (`result.async`), the card goes "in progress", and the worker returns its outcome through its exit code. It **dies when done**; it is not a resident. |

***Worker* is worker in French too.** It is a technical term, like *commit* or *cache*: it is not translated, not in
the code, not in the documentation, not aloud. « Ouvrier » was written once on 11/09, and invented a second name for a
thing that already had one — that is how a synonym settles in and ends up meaning something else.

*A neighbour not to confuse: the **resident** (`residents.md`), which lives as long as the server app. A worker ends, a
resident lasts.*

## What runs

| word | what it means |
|---|---|
| **operation** (*opération*) | everything Vigie runs: action, API write, internal pass, desktop order, installation. Inventory: `../../progress/implemented/operations.md`. |
| **synchronous operation** (*opération synchrone*) | its result is in the answer. |
| **asynchronous operation** (*opération asynchrone*) | the work goes on after the answer, under a busy mark, launched by `Start-Operation`. Protocol: `../../progress/targeting/operations.md`. |

*"short" and "long" (« courte », « longue ») are no longer said: the mode does not depend on duration.*

## Identity

| word | what it means |
|---|---|
| **who runs** (*qui exécute*) | the account the process runs under (`Get-ProcessAccount`). For the server app: the service account. |
| **who asks** (*qui demande*) | the account behind the request (`Get-RequesterAccount`), read from the session cookie. `$null` if nobody has identified. |
| **account secret** (*secret du compte*) | the profile file, protected by an explicit ACL: it is what proves an identity. |
| **sign-in address** (*adresse d'ouverture*) | the **single-use** URL (30 s) the client app presents to open a session. Disposable by construction. |
| **session** | the cookie the sign-in address leaves behind. It **does not expire**. |

## Deployment

| word | what it means |
|---|---|
| **stage** | `dev` or `prod`. **Declared** in `machine.psd1`, never inferred. It governs version tagging, nothing else. |
| **source** | where the deployed code comes from — a setting (`UpdateSource`, `UpdateRemote`), independent of the stage. |
| **shared installation** (*installation partagée*) | `C:\Program Files\Sowapps\Vigie`: what every account runs. |
| **service clone** (*clone du service*) | the copy of the repository the server app synchronises to build a version. The service **never** writes in a person's repository. |
| **installation lock** (*verrou d'installation*) | the `%ProgramData%` file saying an installation is writing right now. It is released at the last change, not at the last click. |
