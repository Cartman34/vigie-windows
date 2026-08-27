# Getting started

[Documentation index](../README.md) · [Français](../../fr/using/getting-started.md)

You have run [the installation](../operating/install.md). Here is what you are looking at.

---

## The tray icon

Once the autostart task is registered, Vigie starts with your session as a **system tray
icon** near the clock. The icon is a gauge, and **its colour is the health of the
application itself**, not of your machine:

| Colour | Meaning |
|---|---|
| Green | the server is running and answering |
| Amber | the server is starting up |
| Red | the server is stopped or failing |

The tray polls the server's `/health` endpoint every 8 seconds, so the colour is never
more than a few seconds stale.

**Double-click** the icon to open the dashboard in a dedicated window. **Right-click** for
the menu:

| Entry | Effect |
|---|---|
| **Show the application** | opens the dashboard in a dedicated window (Edge or Chrome in `--app` mode, so no address bar and no tabs) |
| Open in the browser | opens the dashboard as an ordinary browser tab |
| *Status: …* | not clickable — the current state, in words |
| Relaunch the application | restarts the tray app itself |
| Restart the server | stops and restarts the Pode server |
| Open the logs | opens the server's log folder in Explorer |
| About Vigie | opens the GitHub repository |
| Quit | closes Vigie (the server stops with it) |

The dedicated window needs a Chromium browser. Without one, use "Open in the browser".

## The dashboard

The page is at <http://127.0.0.1:47600/>. A loading screen shows while the first state is
being computed, then the cards appear.

- The **main title is your machine's name**, read at runtime.
- The **coloured strip under the header** is the connection to the API: green = live
  data, amber = mock data (the server is not reachable and the page fell back to a
  bundled sample), red = error.
- The state refreshes **automatically every 60 seconds**, and the page reloads itself
  when a new version of the application is served.

### Reading a card

Each card is one monitored **module**, grouped by theme. On its left edge, a
**coloured strip carries the status of that module** — do not confuse it with the strip
under the header, which is about the API connection.

| Status | Meaning |
|---|---|
| Green | compliant, nothing to do |
| Amber | worth watching |
| Red | a problem |
| Neutral | informational, or not measurable right now |

Inside, each line is a **field**: a label, a value, and its own status. Expanding a field
shows a plain-language explanation of what it is, and — when something is wrong — what
you risk by leaving it and what you can do about it.

A **blinking left strip** means a background task is running on that card (a package
upgrade, an online update scan, a network measurement). The page keeps polling that card
on its own; you can close the browser and the task keeps going.

### Buttons

Buttons carry **the name of the action**, never a generic "Fix". They only appear when an
action actually exists. The icon tells you what will happen when you click:

| Icon | Meaning |
|---|---|
| Triangle | runs immediately |
| Orange warning triangle | asks for confirmation first |
| Checklist | opens a window where you choose what to apply |
| Outgoing arrow | hands over to external software (Windows Settings, Disk Cleanup, Explorer) |

---

## Your first useful thing

Open the **Windows Update** theme and look at the *Update lock* card. It tells you
whether automatic updates are off, whether the ACL lock is applied, how many update
tasks are disabled versus still active, and whether a reboot is pending.

From there, the single button toggles between **"Update mode (unlock)"** and **"Lock
now"**. Both ask for confirmation. Read [Windows Update](windows-update.md) before using
either — that card is the one that changes how your machine behaves.

## Next

- [What Vigie monitors](features.md) — every card, every field, every action
- [Windows Update](windows-update.md) — the lock, in detail
- [Troubleshooting](troubleshooting.md) — the icon is red, the page shows mock data, …
