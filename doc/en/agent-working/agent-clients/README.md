# Agent clients — one file per software that carries an agent

**Everything in this folder is true of ONE agent client and may be false of every other.** That is the whole reason
it is separate: `disciplines.md` binds whoever works here, in any client; these files describe the machine the
agent runs inside, and they expire the day the owner changes it.

**Who it is for.** The owner, so he can say what he means in words the agent recognises, and the agent, so it knows
what its own client does with what it writes. Asked for on 08/10: *"les termes, c'est pas du tout dans la
discipline. Pour moi, c'est dans la manière de communiquer ensemble. Sachant que c'est attribué à Claude
uniquement. Si demain j'utilise Codex, ben, ça se vaudra pas forcément."*

**One file per client, named `client-<name>.md`**: `client-claude.md` today, `client-codex.md` the day there is
one. A file is added when an agent is actually used here, never in anticipation.

**Why the prefix, and it is not decoration.** A file called `claude.md` is loaded AUTOMATICALLY by Claude Code as
if it were a `CLAUDE.md` -- the match ignores case, and Windows ignores it too. It landed in the session's context
the second it was written. That is wrong for this folder: these files are read when they are needed, not carried
in every session. *08/10: "il fait partie de ton amelioration, ca devrait pas etre charge. Que les parents qui se
chargent."* The prefix keeps the name recognisable and the file out of the automatic load.

**What belongs in one of these files**

- The vocabulary of the exchange that only holds for that client — the names of the things the owner and the agent
  point at, in the client's own terms, not in invented ones.
- What the client does with what the agent produces: what it shows, what it hides, what survives a restart.
- Nothing about Vigie. The product's rules live in `../../../progress/`, the way of working in `../disciplines.md`.

**The test, before writing a line here:** would this still be true with another agent? If yes, it does not belong
in this folder.
