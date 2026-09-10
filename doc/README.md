# Documentation — Vigie

Two ways in to **use** Vigie, one per language:

- **[Documentation française](fr/README.md)**
- **[English documentation](en/README.md)**

The repository READMEs: [`README.md`](../README.md) (EN) · [`README.fr.md`](../README.fr.md) (FR).

---

## How this documentation is laid out

| Folder | Audience | Answers |
|---|---|---|
| `fr/using/`, `en/using/` | **user** | How do I use it? getting started, cards, Windows Update, troubleshooting |
| `fr/operating/`, `en/operating/` | **user** | How do I put it into service? install, configuration, security |
| `en/developing/` | **developer** | How is it built, how do I add a card? |
| `agent-working/` | **the agent** | What to know before touching the project, and the rules to hold |
| `progress/` | **design** | What we aim for, what is done, what has been settled |

Four choices explain that shape:

- **Two moments, two folders** — `operating/` answers "I am putting it into service" (install, configure, secure),
  `using/` answers "I am using it" (getting started, cards, Windows Update, troubleshooting). A file in one may link
  freely into the other: they are two views of the same product, not two worlds.
- **File names are technical, therefore English** — even for French content. `fr/install.md` and `en/install.md` carry
  the same name, so the counterpart is found without translating anything. The *content* is in the folder's language.
- **What does not get translated lives OUTSIDE the language folders.** `progress/` and `agent-working/` are
  written in French, the project's language, and address neither the user nor the public; each says so in its own
  `README.md`. The development documentation exists in English only and sits outside for the same reason.
  Nothing requires `fr/` and `en/` to hold the same files.
- **The work queue is never committed.** Where things stand right now and what is left to do live in `local/`, ignored
  by git: it changes every session and belongs to one machine.

**Every folder carries its index.** A `README.md` in each folder lists what the folder holds, and it is the way in:
one walks a path of section NAMES, never a numbered reference, which goes stale the moment something is inserted.
An indexed folder also stops documents citing their neighbours to make up for the missing map -- cross-file
references are then dosed, not sown (**D119**).

**One place per fact.** Each piece of information lives in ONE place and the others link to it. The one deliberate
exception is `progress/`: `targeting/` states the need, `implemented/` states what is really built, and a card may well
be described on both sides. Losing information hurts more than repeating it.

## What does not ship in the published archive

`progress/`, `agent-working/`, `en/developing/security-review.md` and this very file: project documents, of no use
to someone installing Vigie. The build script leaves them out by name, each with its reason
([`scripts/build-release.ps1`](../scripts/build-release.ps1)).
