# Vigie — documentation

**English** · [Français](../fr/README.md) · [Back to the README](../../README.md)

Everything is one click from here, and every page is one click from any other.

> These pages are translated from the French, which is the master version: where the two disagree,
> [the French page](../fr/README.md) prevails.

## For users

| Page | Answers |
|---|---|
| [Installation](operating/install.md) | How do I get it on my machine? Archive or git? How do I remove it? |
| [Getting started](using/getting-started.md) | It's installed — now what? What is that tray icon? How do I read a card? |
| [What Vigie monitors](using/features.md) | Which cards exist, what each field means, what each button does |
| [Windows Update](using/windows-update.md) | What does the lock actually change? How do I install updates? |
| [Security](operating/security.md) | Why administrator? What is exposed? What is the residual risk? |
| [Configuration](operating/configuration.md) | Change the port, point at external tooling, machine-local overrides |
| [Troubleshooting](using/troubleshooting.md) | Nothing opens, the server is down, where are the logs |

## For developers

| Page | Answers |
|---|---|
| [Development — start here](developing/README.md) | Repository layout, how to run from source, conventions |
| [Architecture](developing/architecture.md) | Contract-first design, the four apps, the request path |
| [Probes and actions](developing/probes-and-actions.md) | Add a card or a button without touching the contract or the front end |

## Internal working documents

These are the project's own memory, not user documentation. They are French-only, and
they are deliberately left as they are. They ship with the repository, **not** with the
distribution archive, so the links below point at GitHub.

- [`doc/progress/decisions.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/progress/decisions.md) — every settled decision, numbered `D01`…
- [`doc/en/agent-working/briefing.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/en/agent-working/briefing.md) — where the project stands and what comes next
- [`CHANGELOG.md`](../../CHANGELOG.md) — change history
- [`doc/progress/targeting/features.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/progress/targeting/features.md) — target features, by ID
- [`doc/progress/implemented/status.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/progress/implemented/status.md) — what is really implemented, by ID
- [`doc/en/developing/conventions.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/en/developing/conventions.md), [`doc/en/developing/technologies.md`](https://github.com/Cartman34/vigie-windows/blob/main/doc/en/developing/technologies.md)

## Status

Product version **v0.1** (file [`VERSION`](../../VERSION) at the repository root; the
`v` prefix is added when displaying). **Nothing is published yet** — no release, no
installer, no compatibility guarantee.
