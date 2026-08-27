# Getting started

[Documentation index](../README.md) · [Français](../../fr/using/getting-started.md)

You have run [the installation](../operating/install.md). Here are the five minutes that follow — the detail of every
screen lives elsewhere, and the links are at the bottom of this page.

---

## 1. The icon near the clock

Vigie starts with your session and settles into the notification area as a gauge. **Its colour is the health of Vigie
itself, not of your machine**: green, the server answers; amber, it is starting; red, it is down.

**Double-click** it and the dashboard opens. **Right-click** for the menu, which holds "Restart the server" and "Open
the logs".

## 2. The dashboard

The page lives at <http://127.0.0.1:47600/>. The title is your machine's name. Cards appear once the first state has
been computed, then refresh every 60 seconds.

Each card is a monitored **module**. The stripe down its left edge carries its status: green, nothing to do; amber,
worth watching; red, a problem; grey, informational. Inside, every line unfolds and explains itself in plain words:
what it is, what you risk by leaving it alone, and what you can do about it.

Buttons are named after what they do — never a vague "Fix it" — and only appear when the action really exists.

## 3. Your first useful thing

Open the **Windows Update** module, card *Update lock*. It tells you whether automatic updates are off, whether the
lock is applied, and whether a reboot is pending. A single button toggles between **"Update mode (unlock)"** and
**"Lock now"**.

Read [Windows Update](windows-update.md) before touching either — that card is the one that changes how your machine
behaves.

---

## Going further

- [What Vigie monitors](features.md) — the tray menu, the anatomy of a card, the button icons, then every card one by
  one
- [Windows Update](windows-update.md) — the lock, in detail
- [Troubleshooting](troubleshooting.md) — the icon is red, the page shows mock data, where the logs are
