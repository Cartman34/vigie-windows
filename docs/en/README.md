# Vigie — documentation

**English** · [Français](../fr/README.md) · [Back to the README](../../README.md)

Everything is one click from here, and every page is one click from any other.

## For users

| Page | Answers |
|---|---|
| [Installation](install.md) | How do I get it on my machine? Archive or git? How do I remove it? |
| [Getting started](getting-started.md) | It's installed — now what? What is that tray icon? How do I read a card? |
| [What Vigie monitors](features.md) | Which cards exist, what each field means, what each button does |
| [Windows Update](windows-update.md) | What does the lock actually change? How do I install updates? |
| [Security](security.md) | Why administrator? What is exposed? What is the residual risk? |
| [Configuration](configuration.md) | Change the port, point at external tooling, machine-local overrides |
| [Troubleshooting](troubleshooting.md) | Nothing opens, the server is down, where are the logs |

## For developers

| Page | Answers |
|---|---|
| [Development — start here](development/README.md) | Repository layout, how to run from source, conventions |
| [Architecture](development/architecture.md) | Contract-first design, the four apps, the request path |
| [Probes and actions](development/probes-and-actions.md) | Add a card or a button without touching the contract or the front end |

## Internal working documents

These are the project's own memory, not user documentation. They are French-only, and
they are deliberately left as they are.

- [`docs/DECISIONS-VALIDEES.md`](../DECISIONS-VALIDEES.md) — every settled decision, numbered `D01`…
- [`docs/REPRISE.md`](../REPRISE.md) — where the project stands and what comes next
- [`SUIVI.md`](../../SUIVI.md) — running log
- [`CHANGELOG.md`](../../CHANGELOG.md) — change history
- [`docs/targeting/features.md`](../targeting/features.md) — target features, by ID
- [`docs/implemented/status.md`](../implemented/status.md) — what is really implemented, by ID
- [`docs/conventions.md`](../conventions.md), [`docs/technologies.md`](../technologies.md)

## Status

Product version **v0.1** (file [`VERSION`](../../VERSION) at the repository root; the
`v` prefix is added when displaying). **Nothing is published yet** — no release, no
installer, no compatibility guarantee.
