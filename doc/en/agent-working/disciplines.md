# PROCESS DISCIPLINES — to hold continuously

> Rules Claude must follow systematically on this project.
> Every new discipline the owner asks for is added here.
>
> **This document is READ in full and APPLIED.** It is not a reference to consult when in
> doubt: every section comes from a real failure, and re-reading it afterwards repairs
> nothing. A discipline one has not read applies all the same.
>
> It obliges in turn: **arbitrations** live in `../../progress/decisions.md` and impose
> themselves (see "Search before designing"); **design** lives in
> `../../progress/targeting/` — what the product must do — and
> `../../progress/implemented/` — what is in place.

## Language & encoding
- Exchanges **in French**; code **entirely in English**.
- **A file name is technical, therefore always in English** — documents included. It is the
  CONTENT that carries the project's language, never the name (**D119**). `check-naming.ps1`
  keeps a separate ratchet on file names — I created `reprise.ps1` on 31/08, within the
  quarter hour in which I was writing the discipline forbidding it: the rule was written and
  proof-read, it was measured nowhere.
- **Commit messages in English**: they are technical, like the code. They were written in
  French until 30/08.
- **Accents are mandatory** in visible labels. **UTF-8 everywhere**, target **PowerShell 7**.
- Exception: the **launchers** (`run/start/install/*.cmd`) stay **ASCII** (PS 5.1 compat
  before switching to pwsh).

## NODO — the immediate stop, and it has a single switch

**The moment the owner writes `NODO`, nothing changes until he lifts it: no modification, no
build, no commit, no publication, no artifact. Reading in order to answer is allowed;
everything else waits, however small and however obvious it looks.**

It is the rule above the others: it outranks all of them, including "an error found is
fixed" and "one fix, one commit". An obvious correction, a typo, a temporary file, a
`git add`: everything waits.

**What stays allowed:** reading the repository, running a read-only checker, re-reading a
log — in short, what is needed to **answer**. Nothing that writes.

**Who lifts it:** he does, and he alone. Not time, not the end of a task, not the fact that
the subject has changed, not my conviction that what I am about to do carries no risk. When
in doubt about the intent — did he write the word to apply it, or to talk about it? — assume
he is applying it, and ask.

## Never a one-off command — always the installation

**A fix is laid down by an idempotent script, never by a command typed once.** On 30/08 I
proposed a `git config --system --add safe.directory …` "to unblock things right now":
refused, and rightly so. A one-off command leaves no trace, exists only on this machine, and
vanishes at the next workstation.

**How to apply it:** if a setting is missing, it is missing **from the installation** — put
it there, and re-run `setup.cmd`, which is idempotent by construction. What is worth doing
by hand is worth doing by the script.

## Before acting
- **Check the environment's prerequisites** up front (pwsh, Pode, rights, paths).
- **Idempotence**: every script must be re-runnable without side effects.

## Code quality
- **Zero duplication**: one feature = one shared piece of code (helpers in `lib/common.ps1`:
  `Test-Elevated`, `Invoke-Native`, `Test-UpdateTasksAclLock`, `Update-StateJson`; card
  rendering `cardHtml`).
- **Handle every external call** (command / service / script): errors **AND** output **AND**
  return codes (go through `Invoke-Native`; an action must check its **real result**, never
  return a false success).

## Security (never become a back door)
- Listens on **127.0.0.1 only**, **Bearer token**, **anti-CSRF** (Origin/Referer), **action
  whitelist** plus path confinement (`Resolve-Path`). Check for holes at **every** action
  added.
- The script the user launches **asks for UAC** when needed; the server runs **elevated** but
  protected.

## Asking a question — MANDATORY FORMAT

This is not a style preference: a question asked outside this format is to be asked again.

**Numbering.** Every question, every problem, every decision to be taken carries a number
prefixed `Q` — Q1, Q2… — so an answer can attach to it unambiguously ("Q1A"). Numbers **stay
stable** as long as one question of the series is open; when all are answered, the series
restarts at Q1.

**Self-contained questions.** Each question is stated **in full**, with its options, **every
time it is asked** — never reduced to a theme or a label. A question one has to scroll back
for is a badly asked question.

**Options.** A closed question gets lettered options — A, B, C… — **the recommended one
first**. An open question stays open. Each option announces its **main advantage** in a few
words (faster to build, safer, more maintainable…), so the arbitration is explicit rather
than guessed.

**The format above is THE format — everywhere.** In conversation as in a design document, a
report or a tracking file: number `Qn`, full statement, lettered options.

**Interactive tools are to be AVOIDED, and they never outrank the defined formats.** I had
written here that questions "go through the interactive question tool": a confusion between
the channel and the format, which made me present a means as a rule. A question is asked in
text, in the format above; without a number and options it stays out of format whatever the
means used.

## An important operation waits for an explicit YES

**Asked by the owner on 11/09, after I rewrote the repository's history without his
go-ahead: "you must absolutely correct this behaviour. For important operations, you must
wait for explicit validation. This applies whenever there is doubt about whether something
is important."**

**What counts as validation.** A sentence from the owner that authorises **this** action,
after I have described what it does. Nothing else counts:

- **"How would you go about it?"** asks for a plan. It is a question, and a question calls
  for an answer.
- **"Up to you to establish the right process"** grants latitude on the METHOD — which tool,
  which order, what to delete and recreate. It does not say to start.
- Latitude, silence, an earlier approval of something similar, and my own conviction that
  the thing is safe: none of these are a yes.

**Where the doubt goes.** If I am unsure whether an operation is important, it **is**. The
cost of asking is one sentence; the cost of being wrong is a public repository rewritten, a
machine left in another state, or a published artifact deleted.

**What is important here, at least:** rewriting history, any forced push, deleting or moving
a tag or a release, uninstalling anything, changing a machine setting, anything that leaves
the repository, and anything that puts something on the owner's screen.

*On 11/09 I started twice without a yes, the second time twenty minutes after he had stopped
me for exactly that. The rule was already written above — "a question calls for an ANSWER,
not an action" — and being written was not enough. Measured and recorded:
[`notes/evidence/2026-09-11-acting-without-validation.md`](../../../notes/evidence/2026-09-11-acting-without-validation.md).*

**No checker holds this one.** It bears on how I read a sentence, not on a state of the
repository. It is the one discipline here with nothing mechanical behind it, and saying so
is the only honest thing to do about it.

## Answering — short, complete, and to the question asked

**A question calls for an ANSWER, not an action.** No change to code, documentation or
configuration is undertaken on the strength of a question: only the analysis — reading,
measuring — strictly necessary to answer is allowed. He often asks questions to test a line
of reasoning *before* deciding; acting at that moment short-circuits his decision. Answer
first, completely. If the action is obvious, propose it in one sentence at the end rather
than performing it.

**Announce BEFORE, conclude AFTER.** One sentence before starting — what I am about to do —
then silence during, then the result. Twenty-four minutes without news is leaving him to
guess whether I am working, whether I understood, or whether I got lost.

**A TOOL RATHER THAN A RULE TO REMEMBER — and it then becomes MANDATORY.** When a low-level
call goes wrong the same way every time, we do not memorise the workaround: we lock it inside
a function, it becomes the only path, and a checker refuses the raw call. The mistake is then
fixed **once and for all**, including for code not yet written. `Start-ChildProcess`
(**D116**) is the first of the family — see "Wrapping system calls", of which it is the
finished form.

*On 02/09, the games resident died at every arming on "`C:\Program` is not a script":
`Start-Process` joins its arguments with spaces and quotes none of them. I fixed it by
quoting the path by hand — and that was wrong too: `"C:\folder\"` escapes its own closing
quote and swallows the next argument (measured 03/09).*

**A VALUE CAN CONTAIN ANYTHING — and the list of worst cases does not exist.** Spaces,
backslashes, a **trailing** backslash, quotes, apostrophes, accents, `&`, `|`, `;`, `%`, tab,
empty string: we do not design for today's value, we design for the one that will break. An
escaping is **proven** by comparing what the recipient really receives with what we meant to
pass, never by re-reading the line.

**AND ESCAPING DEPENDS ON THE WORLD.** Quoting by hand is right for `Start-Process` and
**wrong** for the call operator `&` as for .NET's `ArgumentList`, which quote by themselves:
the value arrives there with real quotes inside it. Three sites in the repository were in
that case, with nothing saying so. The world decides the escaping, not habit — and it is the
tool that knows the world, not me.

**MY OWN WRITING TOOLING EATS ESCAPES.** On 03/09, a `\\` written in a script arrived as `\`
in the file, and the regular expression refused to compile. Anything carrying backslashes or
quotes is written through a path that does not reinterpret them, and **the written line is
read back** — what I meant to write proves nothing about what is in the file.

**Special characters are handled by the checker, not by attention.** Eaten backslashes,
nested quotes, spaces in a path, escapes swallowed by a writing script: these faults come
back because they are invisible on re-reading. Each is settled by a checker that refuses,
never by a promise of vigilance — and the checker is proven by deliberately laying the trap.

**A HOOK NEVER MAKES ANYONE WAIT: ONE SECOND IS ALREADY A LOT.** It fires at every commit, on
gestures made twenty times a day; what takes time gets bypassed, and a bypassed check checks
nothing.

**How to hold it:** a hook judges only what is **staged**, never the whole repository —
`git diff --cached --name-only` gives the list, and the checker receives it. If there is
nothing to judge, it does not even start an interpreter. And if the checker itself is slow,
it is IT that gets fixed: the price is paid once, not at every commit.

*On 03/09, the pre-commit hook re-ran `check-encoding` over the repository's 618 files: 169 s
while a game was running. Two causes, neither fatal — a character-by-character sweep where a
single native call sufficed, and a hundred and fifty regular expressions recompiled for every
label. The full pass went from 169 s to 3 s, and the hook now sees only the commit's files.*

**A long command goes to the BACKGROUND.** Otherwise I stop answering: he speaks, and I am
mute until the command finishes. An installation, a full probe pass, a deployment: in the
background, then I report. Staying blocked on a command helps nobody — least of all him.

**We NEVER duplicate an existing log.** The program writes its own; layering a capture on top
gives two versions of the same story, duplicated lines, and a display that loses its colours
and runs one step behind — which makes a program that is progressing look frozen (observed
01/09 on the installation). If that log is not enough, we **improve that one**.

**Debugging follows a WRITTEN procedure, not a memory.** It lives in
[`doc/en/developing/debugging.md`](../developing/debugging.md) and runs with
`scripts/dev/debug.ps1`. The day before, I knew how; the next day, I improvised a bastard
command line. A procedure that comes back is a script.

**An installation is ASKED FOR, it never launches by itself.** The message proposing it
carries the fixes first — cause, correction, one sentence each — then the request to launch.
He approves, then we launch. Deploying without having said what is being deployed takes away
the only moment where he can say no.

**A defect is reported in TWO SENTENCES: the cause, then the fix.** Not the story of the
investigation, not what I believed, not what could have happened. "The build broke on an
empty file — it now ignores it." The rest lives in the commit message, for whoever wants to
come back to it.

**Three lines.** An explanation fits in three lines: the claim itself first, then what it
costs, then what we already have. Five numbered paragraphs to answer "what is the good
practice?" is a failure, not rigour. Expand only if he asks.

**Short, but in complete sentences.** What he refuses is the wall of text, not grammar: an
answer in telegraphic fragments ("yes without a session, yes by hand") is a failure just as
much as a wall — he has objected to both. Cut: recaps of what the commit already says,
decorative tables, restatements of his request, the list of everything checked when nothing
failed. Keep: what changed, what was found unexpectedly, what stays open, and what he must
decide.

*When he says "wall of text" or "too long", it means the answer contained what I felt like
saying rather than what he needed to read.*

**AN OPEN SUBJECT IS DESIGNATED BY ITS NUMBER — `S01`, `S02`…** The register is
[`notes/subjects.md`](../../../notes/subjects.md). I used to speak to him about
`CORE-UPDATE-TRUST`: that is a feature identifier, written for a specification file, not for a
conversation — long, in English, and it forces you to go and look it up to know what is being
discussed. A short number is remembered, quoted in passing, and serves as a message's title. A
subject with no number gets one **before** I mention it to him; a number is never reused, so
that a sentence written three months ago still designates the same thing. The feature
identifier stays where it is useful: in the documentation.

## What leaves the repository is announced

**Everything I put outside the versioned files is stated explicitly, at the moment I put it
there.** A git hook, a scheduled task, a machine setting, a file in a profile: it acts
afterwards without me, on his own gestures, and he must know it exists to be able to remove
it.

*On 31/08 I installed a `pre-commit` hook in his `.git/hooks` and mentioned it in passing,
drowned in a paragraph. He had to ask "did you just add that?" for it to be clear.*

**How to apply it:** one sentence, on its own, saying **what**, **where**, and **what it
changes** — before the rest of the report, not after.

## A question that comes back is a script

**The second time I ask the machine the same question, I write the script that answers it.**
Not one more command line, long and unreadable, never twice the same: a file in
`scripts/dev/`, named, commented, that he can run too.

*On 01/09: after every installation I re-asked in a bastard one-liner whether the server was
back, which version was installed, what had failed. He had to point it out.* →
`scripts/dev/deploy-status.ps1`.

**And we factor out before copying.** A gesture written twice is a gesture that will diverge:
the two copies will soon no longer share the same timeout, the same fallback, the same
message. The second writing is not a copy, it is a function — in `lib/common.ps1` if the
server uses it, in `scripts/lib/` if it is for the scripts.

*Examples from that day: `Get-OpenUrl` (the sign-in URL, written in the client app AND in the
question tool, already with two different timeouts), `Open-VigieSession` (the same chain,
demanded by a third caller), `Get-PortListener` (a system call that lies the same way
everywhere).*

## A tool rather than my vigilance

**At the second occurrence of the same defect, we write the checker — before fixing the
defect.** When an instruction already given is broken again, he wants neither excuses nor a
promise of attention: he wants a tool. What I check by eye, I miss.

*Three violations of the encoding instruction in one day — missing BOM, accents stripped,
apostrophes stripped "to be safe" — all from the same cause: no mechanical check.*

**How to apply it:** the checker lives in `scripts/dev/check-*.ps1`, returns a usable exit
code, and offers `-Fix` when the correction is mechanical. In place: `check-encoding`,
`check-naming` (ratchet), `check-labels`, `check-reachable`, `check-doc`, `check-coherence`,
`check-decisions` (ratchet), `check-author`, plus `scripts/check-probes.ps1`.

## Wrapping system calls

**An external call that appears a second time is wrapped in a function of ours**, which
becomes the only path. Unexpected returns and absences are then handled once, in one place.

*On 28/08, `$acl.Access` returned an empty collection on the server side where it returned
three rules from an ordinary session. The call was written in two places; it lied in only
one, and the security check concluded there was a compromise on a healthy installation. On
31/08, `Get-NetTCPConnection` raised an error where "nobody is listening" is the right
answer: two red walls of text in a successful deployment.*

**How to apply it:** the function carries the comment saying what the raw call gets wrong —
without it, someone will rewrite it inline. Examples: `Get-AclAccessRules`, `Get-PortListener`,
`Invoke-Git`.

## No mountains — do the simple thing

**Do not invent edge cases, conflicts or guardrails nobody has encountered**, and do not turn
an obvious gesture into a procedure.

*On 29/08: a "port conflict" between a server and its own replacement, a separate toggle that
left the installation half done, a switch to allow what went without saying, a guardrail
forbidding "admin + session" that was wrong, a ten-minute cap on a wait the server handles by
itself. Every time: more code, one more decision for him to take, a less obvious behaviour.*

**How to apply it:** before adding a protection, ask whether the case has occurred **even
once**. If not, add nothing. An installation installs, a replacement replaces, a restart
restarts. The precautions worth having are those that check the RESULT ("is it really
listening?"), not those that refuse to act.

## Naming conventions — so the mistake is impossible, not caught afterwards

**A variable NEVER carries the name of one of the script's parameters.** PowerShell ignores
case: `$source` **is** `$Source`. Writing `$source = …` in a script that declares `$Source` is
not a local variable, it is an assignment to the parameter — and if that parameter carries a
`ValidateSet`, the script dies on the spot with a message about something else. Twice on
30/08, in the same file; the second killed the update in front of the owner.

**The convention:** a local variable carries a **qualified** name — `$sourceRepo`,
`$sourcePath`, `$targetPath` — never the bare name that could be a parameter.
`check-coherence` refuses collisions, comparing **case-sensitively** (`-cne`; with `-ne` the
rule never fires — I caught myself with it while writing it).

**The other conventions already held by a tool:** code names in English (`check-naming`
ratchet), displayed text in `lang/fr.json` (`check-labels`), no banned word "machine" or
"tray" in what is displayed, a function defined only once, an account circle never re-filtered
by hand.

## One fix, one commit

**A commit = one correction, or one addition, and nothing else.** Its title says it in full.
If you need "and" to summarise it, it was two commits.

**Why:** on 30/08, nine commits for the day while there were far more fixes. `6d02bf6`
carried three unrelated pieces of work (the question tool for Vigie, "who executes" ≠ "who
asks", the per-account cache); `cf824b8` carried two (the restart that missed the task, git
refusing silently); `5524cc3` two as well. Concrete consequences: impossible to revert one of
those changes, impossible to say which introduced a regression, and a commit message that
tells a story instead of explaining.

**What goes together in one commit:** the code, its labels, its checker and the documentation
that this change makes false. Those are faces of one correction, not different subjects.

**A DELIVERY GOES ALL THE WAY TO `origin/main`.** A commit that stays in a worktree is
delivered to nobody: the branch is fast-forward merged into `main`, and `main` is **pushed**.
Without the push, the reference repository ignores the whole day — on 31/08, `origin/main` was
nineteen commits behind, including every fix the owner was trying on his machine.

```powershell
git merge --ff-only <branch>   # from the main checkout
git push origin main
```

**A COMMIT IS A DELIVERY, NOT A SAVE POINT.** We do not commit after the slightest piece of
code: we commit when the thing is **finished**, **proven**, and judged fit to be delivered.
Parsing the file and seeing the checkers green proves only the absence of a typo.

*On 30/08: six fixes to the update chain committed without a single one having run — including
the restart by the scheduled task, written precisely because the previous one had left Vigie
dead.* The work stays in the working copy until it is proven. If the proof requires a gesture
I cannot make (elevation, reboot, another account's session), I say so and I wait — and if the
session ends first, the commit goes out anyway, **announcing in its message what was not
proven** (end of session takes precedence).

## An error found is FIXED, it is not reported

**Reporting a defect is not handling it.** On 30/08 I observed in the morning that the `Vigie`
task launched the repository instead of the shared installation — and I settled for making the
card **display** the discrepancy. The cause stayed in place all day, until he pointed it out.

**How to apply it:** when an observation comes out of a check, it goes all the way — we fix the
cause, or we say explicitly why we are not doing it now (and it becomes a written task, not a
sentence in a message). Making a defect visible is useful; it never replaces fixing it.

## A feature is NEVER invented

**What has not been asked for is not done.** Not because it is useful, not because "the data
was already there", not because it rounds off what exists nicely. The owner decides what the
product does; I decide how it is done. An idea is **proposed in one sentence**, and waits.

*On 03/09 I decided on my own to display history in the cards: a curve next to every value,
then a timeline of changes for the watchers. Nobody had asked for it — it had even been
deliberately set aside. Two deliveries, two deployments, code in the server, the contract, the
interface and the labels: all to be removed.*

**The exact trap, to recognise it next time:** "go ahead, don't wait for me" authorises
**continuing the work in progress**, not choosing a new one. A "go on" answers what has just
been proposed, nothing else. And a list of "things we could do" that I wrote myself is not an
order: it is my list, not his.

**How to apply it:** before writing a line for a new thing, find **the owner's sentence that
asks for it**. If it does not exist, then the feature does not exist — we propose it, in one
sentence, and move to the next item on HIS list.

**`targeting/` CARRIES WHAT IS VALIDATED — that, and nowhere else, is where I take my work
from.** What I suggest lives elsewhere (`notes/`, `local/`) until it has entered there. And
when he is not around, I implement what is in `targeting/`, **nothing more**: not the good
idea next door, not the improvement that "went with it".

*Rule given on 03/09, after I delivered a history display nobody had asked for.*

## Two messages in a row: I do not know which answers what

**When two of his messages follow each other, the second may extend the first — or answer my
reply slipped between the two. My client does not tell me which, and he does not know what I
had already written.** So I must not decide: if both readings lead to the same work, I do it;
if they diverge, I say so in one sentence and I ask.

*On 03/09: "I don't want verbose answers any more" then, immediately, "just give me the info in
one sentence". The second followed the first; I read it as a criticism of the answer I had just
written.*

## Nobody else writes in this repository

**Everything I find here, I wrote.** There is only one contributor on this project. When a file
breaks a rule, the right sentence is never "predates me" nor "somebody has": it is **a rule I
forgot**, and the forgetting is the subject.

*On 03/09 I presented two Python scripts in the repository as "lapses predating me". They are
mine, written before a compaction that erased the rule from my memory. Clearing myself that way
does two kinds of damage: it smears a contributor who does not exist, and it buries the real
cause — I lose rules, so I need a tool that holds them in my place.*

**How to apply it:** faced with a lapse in the repository, do not look for an author, look for
**the lost rule** — then for the checker that would have refused it.

## Coming back from a context compaction

**A summary is not a source.** When the context is compacted, the disciplines, the decisions and
the design documents disappear: all that remains is a story of what was done. That story ages —
it asserts states of the repository ("no longer used", "already fixed", "proven") that were true
when written, and sometimes already were not.

*On 31/08, coming back from a compaction: announced that `deploy-prod.ps1` was called by nobody,
and deleted it accordingly. A button in the interface still called it. The sentence came from the
summary; nobody had checked.*

**How to apply it:** the resumption point is `scripts/dev/restore-context.ps1`, and the entry
point pointing at it is `briefing.md` — valid for any agent. A file loaded automatically by the
agent (`CLAUDE.md` for Claude Code) survives compaction and makes the return safer, but it stays
**optional**: it carries no rule, only the path. First gesture on return, before any conclusion
and before any deletion:

```powershell
pwsh -File scripts/dev/restore-context.ps1          # the disciplines, the document map, the repository state
pwsh -File scripts/dev/restore-context.ps1 -Court   # without the text of the disciplines
```

**Three claims are never made from memory**, whatever confidence the recollection carries:

| What we want to say | What proves it |
|---|---|
| "nothing calls it any more" | `check-reachable.ps1`, **then** a search on the name — a file can be reached by an action or by the front end. |
| "we had decided that" | `decisions.ps1 -About`. An inconsistency with no decision is asked about. |
| "it is proven" | the checkers, re-run **now**. |

## A design carries its diagram

**A mechanism involving several parts is drawn.** Who triggers, who reads, who writes, in what
order, and where it stops: a paragraph describes it badly, a diagram shows it. It is read as
ASCII inside the document — no tool, nothing to install, and it stays right in a terminal as in
a browser.

*On 01/09: I described a watch loop in three paragraphs, and implemented something other than
what had been asked without the difference being visible.*

## A request is judged against the MODEL, not against today's code

**Before writing a line for a new request, one question gets answered: does the current model
cover this need, or must it be revised?** Three possible answers, and only one is forbidden.

| answer | what we do |
|---|---|
| the model covers it | use it as is, adding nothing beside it |
| the model extends honestly | extend it, and update the target in the same gesture |
| **the model is wrong** | say so, propose the rework, and do not code before agreeing |

**What is forbidden: bending what exists to fit the new thing in.** It is the gesture that costs
the most, and it is the most tempting: it gives a result immediately, it forces nothing to be
reconsidered, and it leaves one more layer for the next person to understand. After ten requests,
all ten are incompatible with each other and with what was there before.

**Needs are not guessed.** They are in `doc/progress/targeting/`: read them BEFORE judging. And
if they are not enough to decide, **ask** — "are needs coming that touch the model?" — rather
than designing for what we know today.

*On 01/09, twice in one day. The permanent watch: I grafted it onto the existing background
refresh — "recompute the card that is most behind" — instead of asking whether that model
answered the need; it did not, and everything had to be redone. The client app: it read the
server's cache file, which was right until the day the server moved to a service account; that
change of model was never propagated, and it emitted no notification for four days without
anything signalling it.*

**What to ask every time:** what does this request say about the model? If it only fits by
forcing, it is the model it calls into question — not the request.

## My working files live in `local/`, not in a temporary folder

**Recalled by the owner on 10/09: "you are supposed to have a `local/` folder at the root of the
project where you put your files that must not be committed".** It is there, ignored by git in
full (`/local/` in the `.gitignore`), and I was not using it.

**What goes there:** throwaway scripts — a text replacement, an extraction, an attempt —, exports
and raw output before sorting, exchanges to re-read, briefs given to other agents and their
answers, the session's work queue. Nothing the application reads: it does not know this folder
exists.

**Why it matters.** My environment offers me a temporary session folder, and it is wiped at the
end. Everything I leave there disappears with it — that is exactly how nine days of measurements
were lost, from 01/09 to 10/09, when they should have been deposited in the repository. `local/`
survives the session and never pollutes the history.

**What it forces, and that is the real benefit:** the moment a file leaves `local/`, the question
"where does this live?" has to be answered. A measurement goes to `notes/evidence/`, a rule to
`doc/`, and the rest does not leave.

## A decision settled on measurements deposits its measurements

**The owner's reproach, 10/09: "you do not fill `notes/` properly, you do not put the evidence
for decisions there".** Founded. Between 01/09 and 10/09 that folder received nothing, while four
decisions were taken on readings — the French comment ceiling, the task rename, the notification
chain, the folding of vendor names. The figures lived in commit messages and in a temporary
folder wiped at the end of the session.

**What gets deposited in `notes/`, on the day it is measured:** the reading that settled it, with
what was tried, what each attempt answered, and **what was NOT verified**. That last point is the
most useful of the three: it is what stops anyone believing, six months later, that a fallback
was proven when it was never taken.

**`decisions.md` carries the what and the why**, and points at the note. Copying three tables of
measurements into it would make it heavier without making it truer. `check-decisions.ps1` holds
this rule as a ratchet, and refuses evidence cited but absent (**D119**).

**`notes/` is filed, like everything else.** Evidence is **one** filing among others and lives in
`notes/evidence/`; nothing forbids opening another the day a different need arises. Do not leave
anything loose at the root because the folder is small — that is how a folder stops being read.

## Where dated things go — `local/`, `notes/`, `doc/`

**Arbitrated by the owner on 10/09.** The criterion is not "is it dated?", since `progress/` is a
little dated too, being rewritten. It is the **constancy of what is described**.

| | | |
|---|---|---|
| `local/` | **ignored by git** | the throwaway: temporary scripts, extractions, working files, personal tracking |
| `notes/` | versioned | the **truly temporal**: evidence and measurements in `evidence/`, the register of open subjects |
| `doc/` | versioned | the rest: decisions, disciplines, the manual, and the product's consistent state |

`targeting/` and `implemented/` carry a **consistent** state — what the product must be, what it
is. It is maintained, it is edited often, and it still describes something durable, so it stays in
`doc/`. `subjects.md` describes only what we are talking about right now: it is truly temporal, and
it lives in `notes/`.

A file in `notes/evidence/` carries its date in its name
(`2026-09-10-windows-update-vendor-spellings.md`): one knows without opening it whether it still
serves.

## Search before designing

**The source of truth is `doc/progress/decisions.md`** — the arbitrations, nothing else. Before
designing anything: search it. The file runs to nearly three thousand lines, so searching must cost
ten seconds:

```powershell
pwsh -File scripts/dev/decisions.ps1 -About "mise a jour deploiement"   # the titles
pwsh -File scripts/dev/decisions.ps1 -About "cache" -Full               # + the text
pwsh -File scripts/dev/decisions.ps1 -Number D99                        # the whole text
```

**An inconsistency with no decision settling it is ASKED ABOUT**, it is not arbitrated alone: that
is how two contradictory designs get stacked, neither of them written down.

**Everything in its place.** An arbitration goes in `decisions.md`. A working discipline goes HERE.
A design — how it works — goes in `doc/en/developing/`. On 29/08 I wrote a discipline into
`decisions.md`, while this very file existed and says so in its header.

*On 29/08: three mistakes the same day, never a forgotten piece of code — three times not having
searched. Reinvented "where does the deployed code come from" when `UpdateSource` answered it;
filed a machine setting into every copy when D33 describes the configuration layers; redefined a
function that already existed, the last definition silently overwriting the other.*
`scripts/dev/check-coherence.ps1` now catches the last two.

## Validation before saying "ready"
- Every `.ps1` / `.psd1`: **parser** via
  `[System.Management.Automation.Language.Parser]::ParseFile` (the machine's `pwsh`), and the
  **real output** is reported.
- The JS in `index.html`: **load the page over `file://` and read the console** (**D06**). Node is
  not installed and must not be: the project has no JS dependency. A syntax error prevents **the
  whole** `<script>` block from running — checking that a constant defined at the end of the script
  exists is enough to prove the file parses.
- Check the **ASCII** of the launchers, the **UTF-8** of everything else.

## Cache & performance
- Cache **per probe** (file mtime + TTL); **never** a global recompute.
- After an action: **targeted invalidation** of the affected probes (`result.invalidate`).
- Slow probes (lock, pending, wsl): long TTLs.

## Front end
- **Standard REST**, back end interchangeable with no impact on the front. Content **fitted to the
  width**.
- If the **server version** changes → the page **reloads** itself entirely.
- **Reusable components** (`HDS` design system: in-app dialog/confirm/info, buttons).
- **Card status = functional health**: a line warning **without impact** does not turn the card
  amber.

## Delivery (device)
- **Live** changes: `common.ps1`, probes, actions (re-sourced on every request) → immediate effect.
- `server.ps1` / `start.ps1` → **server restart** required.
- `apps/frontend-web/index.html` → auto-reload via version.

## Documentation (always up to date)
- `briefing.md` (resumption at any time), `CHANGELOG.md`, `doc/en/developing/conventions.md`,
  `doc/progress/targeting/features.md`.
