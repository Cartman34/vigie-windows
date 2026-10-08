# Claude Code — what is true of this agent client, and of no other

**Read the folder's `README.md` first**: everything here describes the software that carries the agent, not the way
of working. With another agent, none of these words mean anything.

## The two kinds of message, and they are the API's own terms

The owner asked for **recognised** vocabulary rather than words invented here, so that saying them to any Claude
works: *"il faut que n'importe quel agent Claude puisse comprendre ce que je veux dire en le disant."* (08/10)

An assistant message carries a list of **content blocks** — each with a type: `text`, `thinking`, `tool_use` — and
the message ends with a **`stop_reason`**. Two of its values matter in conversation:

| What he means | What he says | What it is |
|---|---|---|
| The line written before the work starts | **a `tool_use` text** | a `text` block in a message whose `stop_reason` is `tool_use`; the turn continues, the tools run, control comes back to the agent |
| The message that closes the turn | **an `end_turn` text** | the `text` block of the message whose `stop_reason` is `end_turn`; control returns to him |

`stop_reason` also takes `max_tokens`, `pause_turn` and `refusal`. They play no part in this.

## What the desktop client does with a `tool_use` text, and the CLI does not

**The Claude Code desktop client HIDES the `tool_use` texts once the `end_turn` text is posted.** He sees them
while the work runs, then they are gone. On the CLI they stay — he can quit, come back, and they are still there.
Measured by him on 08/10: *"sur Claude CLI, ça reste affiché, même si je quitte, je reviens, les messages texte de
tool use restent. Mais pas sur le desktop, il préfère les masquer."*

**This is not in the API.** Nothing in a content block or in `stop_reason` marks a message as temporary — the
Messages API keeps every block of every assistant message. Hiding them is a choice of that one client, which is
exactly why it is written here and not in `../disciplines.md`.

## What follows from it, for anything he must keep

**A confirmation given only in a `tool_use` text is a confirmation he ends up without.** He works in the desktop
client. So anything he has to be able to re-read — a confirmation, a list he approved, a number he will act on —
goes in the `end_turn` text as well, and the `tool_use` text is there to let him see it immediately and interrupt
if it is wrong.

That cost him four requests on 07/10 before either of us understood why:
[`../../../../notes/evidence/2026-10-07-four-times-told-to-start.md`](../../../../notes/evidence/2026-10-07-four-times-told-to-start.md).

## And a `tool_use` text does not stop the turn

Writing before calling a tool ends nothing: the tools run and control comes back. A turn ends on its `end_turn`
text, and nothing else. His own messages, sent while the work runs, arrive attached to a tool result inside the
running turn — they interrupt nothing either.
