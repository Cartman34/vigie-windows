# Debugging — one procedure, the same every time

Author: Florent HAZARD <f.hazard@sowapps.com>

When something does not work, the question "how do we look again?" must not come back. It has an answer, and that
answer is a script: [`scripts/dev/debug.ps1`](../../../scripts/dev/debug.ps1).

```powershell
pwsh -File scripts/dev/debug.ps1                     # what can be debugged
pwsh -File scripts/dev/debug.ps1 probe gaming        # a probe, run for real
pwsh -File scripts/dev/debug.ps1 sentinel            # the declared sentinels
pwsh -File scripts/dev/debug.ps1 sentinel internet   # its value now + its history
pwsh -File scripts/dev/debug.ps1 server              # the server app and its log
pwsh -File scripts/dev/debug.ps1 client              # the client app and its log
pwsh -File scripts/dev/debug.ps1 install             # the latest installation
pwsh -File scripts/dev/debug.ps1 card gaming         # the card as Vigie renders it
```

Every target does the same thing, in the same order: it **says what it runs**, runs it the standard way, then shows
**where the log is** and its last lines.

## The four rules that hold for everything

**1. In a real console, without redirecting the output.** A redirected output loses its colours *and* shows one step
late: the program looks frozen while it progresses. Worse, a Windows console in **selection mode** (a click in the
window) pauses the program at its next write — it waits for a key, nothing else. On 01/09 the installation seemed stuck
for twenty minutes for that reason alone; **Esc** or **Enter** set it going again.

**2. Never a second log.** The program already writes its own. Adding one on top gives two versions of the same story,
duplicated lines, and a chance to open the wrong file. If that log does not say enough, **that one is improved**.

**3. What is unreadable here is asked of Vigie.** From an ordinary session, the service account's profile, its logs,
its tasks and the history are **refused** — and a refusal says nothing about the computer, only about my rights. The
server app sees everything: [`ask-vigie.ps1`](../../../scripts/dev/ask-vigie.ps1) takes the client app's road and
returns the facts **as Vigie sees them**.

**4. An action or a worker is not run to see.** Running them for real is an **integration** test: it is **asked** of
the user, every time (**D62**, **D63**).

## What proves what

| What we want to know | What proves it |
|---|---|
| Does a probe return what we believe? | `debug.ps1 probe <id>` — it really runs, its output is **observed** (D43) |
| Does a rare branch work? | `VIGIE_FAKE_<WHAT>` — see [modules.md](modules.md) |
| Does watching run **in production**? | the history of a **new** sentinel: its first line can only have been written by the server loop |
| A sentinel that has not moved | proves **nothing**: without a change, nothing is written — that is the principle |
| Is the deployment in place? | `debug.ps1 install` — versions, server, then the installation log |

## When nothing answers

In order, skipping none:

1. **Is the server up?** `debug.ps1 server` — otherwise nothing else makes sense.
2. **Is an installation running?** An installation lock silences watching and recomputes, on purpose.
3. **Is the console paused?** See rule 1: click in the window, **Esc**.
4. **Is it a refusal of rights?** Then it is not a fact about the computer: go through `ask-vigie.ps1`.
