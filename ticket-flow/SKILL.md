---
name: ticket-flow
description: The one-ticket-at-a-time build loop — stage 1 specifies, stage 2 implements test-first, stage 3 reviews and merges. Use when a session receives a bare ticket ID, or when asked to run a stage of the ticket flow. The unattended driver is the `sweatshop` skill.
---

# Ticket flow

One ticket at a time. The human fires each stage by hand, in a clean session.
**The ticket is the contract; the commit is the handoff** — no intermediate
document. A trivial task goes straight in, no loop.

**This file owns the build loop, and it is the only copy.** Where tickets live and
how triage labels them come from the repo's `docs/agents/issue-tracker.md`, written
by `/setup-matt-pocock-skills`. That skill and the ones the stages call are
**vendored: never edit them to fit this loop.** They get reinstalled, and an edit
there disappears without a word. What the loop needs and they do not define is
defined here, in "What this loop adds" below — nowhere else.

## Two things to read before acting

1. `docs/agents/issue-tracker.md` — where tickets live, and the triage vocabulary
   if `triage` is in use. Missing? The repo was never set up: tell the user to run
   `/setup-matt-pocock-skills` and stop.
2. The `## Bindings do fluxo` block in `AGENTS.md` (or `CLAUDE.md` if there is no
   `AGENTS.md`) — gate command, base branch, model per stage. Missing? See the
   last section. **Never guess the gate command.**

## Stages

| # | Skill | Delivers | Stops and reports if |
|---|---|---|---|
| 1 | `grill-proxy` → `to-spec` → `to-tickets` | `spec.md` + one ticket file per ticket, `Stage: to-implement` | the human does not approve the seams or the slicing |
| 2 | `tdd` | branch named for the id, `Stage: implementing`; alternating **test-only commits, red for the right reason**, and production-only commits; gate evidence; `Stage: to-review` | the ticket needs more than one seam (back to stage 1), or a committed test proves the *contract* wrong — a criterion that cannot hold, a seam that does not exist (`Stage: blocked` + reason). A test wrong only in its harness is not a stop (below) |
| 3 | `code-review` (Standards + Spec axes) | small fixes; then either merge, or a PR that waits | a finding is large — reopen the ticket, back to stage 2 |

Stage 1 also registers new ids in the repo's plan document, if it has one, at the
position of the original. That is the only edit anyone makes to the plan.

Stage 1 selects a few end-to-end acceptance scenarios from the original product
goal, in `spec.md`: input, observable outcome, independent reference when useful,
and who can verify it. These are feature acceptance, separate from individual
ticket criteria. For each test seam, explain to the owner which mistake it can
catch, which can escape, the cost of the alternative and how to reverse the
choice. Use a small experiment when that makes the trade-off understandable.
If `grill-proxy` is unavailable in Codex, use `grilling` with every question to
the human; install the wrapper as described in this skills repository's README.

Refactoring outside what the ticket touched is not part of any stage. It becomes
its own `CLEAN-*` ticket.

Two overrides on the skills the stages call:

- **Stage 2 does not re-negotiate seams.** The `tdd` skill writes no test at a
  seam the user has not confirmed; here the ticket *is* that confirmation — its
  Primary files and its "Tests stage 2 writes" section name the seams, approved
  when the human approved the ticket. Stop only if the ticket needs a seam it
  does not name, which is the back-to-stage-1 case.
- **Nobody refactors mid-loop.** `tdd` parks refactoring in the review stage; the
  review parks anything outside the ticket's Primary files in a `CLEAN-*` ticket,
  except documentation the change made stale, which it fixes (below).

## Stage

    Stage: to-implement | implementing | to-review | reviewing | to-merge | done | blocked

This is the loop position, and it is **not** the triage `Status:` line. Different
axes: `Status: ready-for-agent` with `Stage: reviewing` is a coherent ticket. Never
merge them into one field, and never read one as the other.

**No stage change without a commit.** The stage is what the next session
dispatches on; a stage that moved in a dirty working tree is a stage that can lie.

| Transition | Who | In which commit |
|---|---|---|
| → `implementing` | stage 2 | the test-only commit, its first |
| → `to-review` | stage 2 | its last code commit, gate green |
| → `reviewing` | stage 3 | only if it commits a fix of its own |
| → `done` | stage 3 | the same commit as the ledger line |
| → `to-merge` | stage 3 | the commit the PR is opened from (no-session flow only) |
| → `to-implement` | stage 3 | the reopen commit |
| → `blocked` | anyone | with the reason under `## Comments` |

## What this loop adds

`to-tickets` publishes a local ticket as `# <NN>: title` with a
`**Status:** ready-for-agent` line and checkbox criteria. That is a triage queue
entry, and it cannot carry this loop: no address to cite in a commit, no field to
dispatch on, no declared boundary. **When stage 1 publishes to local files, write
this shape instead of that skill's template** — and change nothing else about how
that skill works. Its vertical slicing, blocking edges, expand–contract sequencing
for wide refactors and the approval quiz are why it is being called.

    # <AREA>-<NNN>: <Ticket title>
    Stage: to-implement
    Blocked by: <the ids that gate this one, or "none">
    Review: agent | human
    Difficulty: normal | hard

    - Primary files:
      - <path the ticket may touch> (<scope, when the whole file is not in play>)
      - New: <path>

    #### What to build

    The end-to-end behaviour this ticket makes work, from the user's
    perspective, not a layer-by-layer implementation list.

    #### Acceptance criteria

    1. <criterion, stated so a test can fail it>
    2. <criterion>

    #### Verification

        <the commands that prove it, gate last>

    ## Tests stage 2 writes (own commit, red)

    - <which file, at which seam, red for which reason before the change>

    ## Comments

Six additions, and each earns its place:

- **The id.** `<AREA>-<NNN>`, **unique across the whole repo** and **immutable** —
  it is the address every ledger line, commit message and review block cites. The
  filename keeps the vendor's positional prefix as well
  (`<NN>-<ID>-<slug>.md`): the number is dependency order and may go stale, the id
  never does. Reuse a prefix already in use before inventing one; next number is
  the highest existing for that prefix anywhere in the tracker, plus one
  (`grep -rhoE 'BUG-[0-9]+' <tracker> | sort -t- -k2 -n | tail -1`). A ticket that
  turns out to belong to another area keeps its id and says so in its body.
- **`Stage:`.** Its own section, above. It is a second line, never folded into
  the vendor's `Status:` — different axes.
- **`Primary files`.** `to-tickets` says to keep file paths out of a ticket because
  they go stale. True of prose; this list is not prose, it is the boundary — the
  implementer may touch those files and nothing else. Keep it to the files in
  play, never an implementation plan. The ADR or doc that describes a mechanism
  the ticket changes is in play.
- **Numbered criteria**, not checkboxes, so a review can fail "criterion 5" by name.
  Each one satisfiable: before publishing, check every criterion against the
  others and against the physics or spec it rests on. Measured 2026-10-01: PHY-45
  criterion 2 (no length jump at the wrap switch) could not hold, and it took a
  reopen and a `Proxy decided` to rewrite it.
- **`Review:`.** Who clicks merge. `agent` (the default when the line is missing)
  lets stage 3 merge an approved PR itself; `human` holds the PR for the person.
  Stage 1 sets it when writing the ticket — the author decides what they want to
  see, not the reviewer. Inside a session branch (below) nothing is held: `human`
  only puts the ticket at the top of the session PR.
- **`Difficulty:`.** Which implementer the driver sends: `hard` gets the lineup's
  `hard` model, `normal` (the default when the line is missing) gets stage 2's.
  Stage 1 sets `hard` when a first pass is likely to miss: criteria that interact,
  numerical or concurrent logic, a function many callers lean on. In doubt, write
  `normal`; the driver escalates any ticket after its second reopen anyway. A
  ticket that looks harder than `hard` is two tickets: slice it again.

Also per effort directory: `ledger.md`, a `| Data | ID | Commit |` table of closed
tickets, one line each, written when a ticket reaches `done`.

### Delivery disclosures

Before closing, record `Acceptance: passed | <evidence link>`,
`Acceptance: pending | <what remains and evidence>`, or `Acceptance: unknown`.
This describes product acceptance; `Verdict: Approve` describes the ticket's
implementation. Missing legacy acceptance remains unknown.

For each contract change, pending product check or unresolved known defect use
one line: `Disclosure: decision|pending|deferred | none|integration|release|unknown | <evidence link and explanation>`.
Choose one value per column. `integration` requires resolving the item before
integration; `release` may permit session integration but remains a release
condition. Link a decision/review or open follow-up ticket. Preserve existing
`Proxy decided` and `Débito humano` text; these legacy lines also enter the PR,
with unknown impact when their evidence does not specify it. An accepted deferral
records who accepted it, why and its impact, rather than relying on a missing
Priority or a closed ticket comment.

## Dispatch on a bare ID

A session handed nothing but an id (`OBS-004`) finds the ticket — the tracker file
says how, usually `grep -rl '<ID>' <tracker path>` — and dispatches on `Stage`.

**Find the loop's base first.** It is the bindings' base branch — unless a
`sweatshop/*` branch exists that is not merged into it (`git branch --list
'sweatshop/*' --no-merged <base>`, remote too). Then *that* is the base for
stages 2 and 3: branch from it, rebase onto it, merge into it. It is the
`sweatshop` driver's session branch, collecting every ticket of a run into one
PR for the human. With no such branch, nothing below changes.

**Find the ticket's branch before reading `Stage`.** Resolve
`sweatshop/scripts/ticket-state.ps1` from this skills installation and run
`powershell -NoProfile -File <helper> -Repo <repo> -Id OBS-004 -IncludeRemote`.
This read-only command is the discovery contract for dispatch, standup and the
driver: exact lowercase ID or uppercase `<ID>[-slug]`, optionally prefixed;
preserved `recovery/*` and old `-asked-<time>` attempts are excluded. Multiple
active names or divergent local/origin copies stop for explicit reconciliation.
Linear local/origin history selects the descendant; a local stage commit ahead
of origin is normal. To resume a remote ref, create its tracking local branch if
absent; fast-forward an existing local branch only when it is an ancestor.
Preserve work and reconcile divergence explicitly.
Read committed ticket text from its unmerged branch, except `blocked` on the
loop's base wins. A merged branch uses the loop's base. An unmerged branch saying
`done` is an invalid handoff: preserve it and repair the merge or reopen; it does
not satisfy dependencies. Only then dispatch:

| Stage | What you do |
|---|---|
| `to-implement` | Stage 2. Call the `tdd` skill. |
| `implementing` | A session stopped mid-run. Report what the branch holds and stop — do not continue blind. |
| `to-review` | Stage 3. Call the `code-review` skill. |
| `reviewing` | Same as `implementing`: report and stop. |
| `to-merge` | The PR waits on the human (no-session flow only). Report it and stop. |
| `done` | Nothing to do. Say so and stop. |
| `blocked` | Report the reason from `## Comments` and stop. |

Three guards:

- **Reconcile `to-implement` from the base with the committed branch.** The base
  copy may be stale: discover the active branch and read its Stage before
  dispatch. If that branch itself says `to-implement` after a reopen, stage 2
  resumes the retained work.
- **Wrong model, no work.** Inside a session branch (below), skip this guard:
  the driver picked your model, maybe from a lineup given only on its command
  line. Otherwise read every `Models` line of the binding (`Models:`,
  `Models (<lineup>):`). Each line is a lineup, and one lineup can mix runtimes,
  so do not look only at the line named for yours. If no line gives this stage
  to your model, say which models do and stop. Codex does
  not tell a session its model name: there, trust the `--model` you were
  launched with and stop only when you know you are a different model.
- **Reopened tickets look new.** `Stage: to-implement` on a ticket that carries a
  stage-3 review section means only the ❌ items are left, and the work continues
  on the existing branch. Read the ticket to the bottom before starting.

## The rules that hold the loop up

**Each red/green cycle separates tests from production.** The load-bearing check is
the `diff --stat` separation, not any agent's promise. Whoever writes the tests
does not make them pass in the same commit, and stage 2 does not touch test files
in a code commit. Later test-only commits and harness corrections are valid:
each relevant cycle records its own red/green proof. This rule exists because green tests have sat on top of a broken
parser — the tests were exercising a copy of the logic.

**A committed test wrong in its harness is fixed, not escalated.** Timing, a
broken helper, a mutant the criteria cannot tell apart from the real code: fix
the test in its own test-only commit, prove it red again for the right reason
(against the base, or by mutating the production code), and say what was wrong
under `## Comments`. A surviving mutant that no criterion can separate is recorded
as equivalent, with the reason. Only a test that shows the criteria themselves
cannot hold stops stage 2. Measured 2026-09-30: four of fifteen stage-2 runs
stopped on the old wording; the proxy answered all four without the human, three
of them with exactly this fix.

**Stage 2 reads around its change before the red test.** List the callers of every
function it changes and the degenerate inputs the change itself creates (an empty
set, a singular system, a value at the boundary), and give a test to any of them
the change could break. A regression is a reopen whatever the criteria say.
Measured: APP-025 (2026-09-29) broke a caller one grep away; PHY-41 (2026-09-30)
turned two collinear ropes into a singular system. Both reopened, both
`S2-implícito`.

**Primary files and the numbered criteria are the contract.** Stage 2 reads those
two lists and treats them as binding. A requirement stated only in prose is
invisible: it gets met by accident or not at all.

**Small fix, or back to stage 2.** Comments, stale documentation and tiny obvious
corrections inside Primary files may be fixed in review. Meaningful production
behavior authored during review, including test-exempt tickets, gets a fresh
independent review of the added diff before approval. Prefer reopening to stage 2
for behavioral repairs needing new tests or source outside Primary files; if a
reviewer already wrote such a repair, preserve it and hand it to another reviewer.
Record author, independent reviewer, examined diff and verdict in Resolution.

**Documentation the change made stale is a small fix wherever it lives.** A
comment, an ADR or a design note that now describes the old mechanism changes no
behaviour and needs no test: stage 3 corrects it in its own fix commit instead of
opening a `CLEAN-*` ticket. Measured 2026-10-01: three docs-only `CLEAN-*` tickets
for ADR-0004 cost 20% of a run, a full stage-2 and stage-3 cycle each.

**Stage 3 reviews against the written contract, every finding in one pass.**
A reopen is earned by one of three things: a numbered criterion the code does
not meet, a Primary-files or test-first rule broken (inspect every commit's
`git diff --stat`: test-only red cycles alternate with production-only changes,
with ticket metadata allowed in either), or a regression — the
change broke something that worked before it. A requirement the criteria do not
state is none of these, however sensible: it becomes a `CLEAN-*` ticket and the
review approves on the criteria as written. Stage 3 never rewrites a criterion's
text; only stage 1 does. Read the whole diff before writing the verdict. In the first review block,
record the affected callers, failure paths and cross-feature interactions examined,
and any not examined; the numbered criterion verdicts remain the acceptance record.
List every finding in that verdict — a finding held back for the next pass costs a
full stage-2 cycle. A re-review checks the ❌ items and the diff since the last
review; a new finding in code the previous pass already read is named as that
pass's miss. Measured 2026-09-24: SYN-010 took two extra cycles (52% of its
time) for findings that were all visible in the first pass, two of them new
requirements.

**Every confirmed unresolved finding has an open destination or an explicitly
accepted deferral.** On an open ticket it goes under `## Comments`; on a closed
ticket, create/link an open follow-up or record who accepted deferral, why and
integration/release impact. A comment on a closed ticket alone is not scheduled
work. Link the original ticket for history. Only stage 1 moves a comment into the body, and
when it does it adds the file to Primary files and a numbered criterion. An
unfolded comment is a note, not a requirement: prose in a body that no file and no
criterion backs is invisible to stage 2, which will ship green without it.

**Red-green proof before reporting.** Show that the new tests fail without the
change and pass with it. Report the real suite counts, not rounded ones. Every bug
fix has a test that would fail without it, and that test calls production code,
never a copy of it.

**Reopening.** A review that knocks down a closed ticket sets
`Stage: to-implement`, marks which criterion fell (❌ with the reason), removes the
ledger line, and appends a review block saying what is left. The block's
verdict line is `Verdict: Reopen — <what fell>`: the driver counts those lines,
and the second one makes the driver park the ticket for the foreman to diagnose
the cause before retrying (foreman, section 2). The next stage 2 still uses the
`hard` implementer when configured; that escalation does not settle a contract
gap or an earlier review miss.

## Commits and closing

Conventional Commits in English, the body saying why and citing the id
(`fix: ... (BUG-003)`). Never squash.

Stage 3 closes by appending a `#### Resolution (YYYY-MM-DD)` block to the ticket —
decision, files, red-green proof, gate output — and adding the ledger line, in the
same commit as `Stage: done`. **The ticket is the memory between sessions.**

### Gate evidence at handoff

Commit the code to test, then run the bound gate once in the foreground through
`sweatshop/scripts/gate-evidence.ps1 -Repo <repo> -Command '<Gate>' -Log <absolute external log> -Receipt <absolute external JSON>`.
The helper captures output, actual exit status, log hash and the tested commit.
Filter that log for counts/errors. Reuse its receipt when code is unchanged;
rerun only after changing code, never merely to produce paperwork. Append
`Gate evidence: <absolute JSON path>` to the ticket in the handoff commit.
Between the tested commit and handoff only this ticket and its feature ledger
may change; skills, scripts and other documentation invalidate the receipt too.
The driver checks receipt, log and equality of tested production at `to-review`, `to-merge` and
`done`. Missing or stale evidence parks the ticket with preserved work. Logs and
receipts are local execution evidence; summarize/link durable verification in
Resolution for another machine's review. A legacy missing receipt is unknown,
and the next stage needing a new handoff must create valid evidence.

The review's **verdict** is one line, and it is the first line of the Resolution
block: `Verdict: Approve`, or `Verdict: Needs your call: <one sentence why>`.
The findings follow. "Needs your call" is for anything the reviewer is not
confident about, including a small fix it made itself that it would rather have
a human glance at. A wrong "Approve" costs more than a held ticket.

Merge depends on the loop's base:

**Into a session branch** (a `sweatshop/*` is open):

1. Rebase the ticket branch onto the session. Verify gate evidence for that code;
   reuse the green run if no production changed during rebase or review.
2. A conflict inside the ticket's Primary files: resolve it. Outside them:
   `Stage: blocked` with the conflict under `## Comments`, commit, stop.
3. `git checkout <session>; git merge --no-ff <ticket branch>`, then the
   Resolution block, the ledger line and `Stage: done` in one commit on the
   session. No PR, no push: the driver pushes and opens the session PR when the
   run stops, every verdict in its body. `Review:` holds nothing here.

**Into the bindings' base** (no session), always through a PR:

1. Rebase onto the base; verify gate evidence, push, `gh pr create`.
2. Post the review as one PR comment, verdict first.
3. `Review: agent` and the verdict is `Approve`: wait for CI
   (`gh pr checks --watch`), then `gh pr merge --merge --delete-branch`, pull the
   base branch, set `done` there with the ledger line. Never squash.
4. `Review: human`, or the verdict is `Needs your call`: set `to-merge`, leave
   the PR open, stop.

## Unattended runs

The `sweatshop` skill's driver feeds bare ids to fresh Claude Code or Codex CLI
sessions, one at a time, and reads `Stage:` back. It adds no instructions of its
own: everything a session
does, it does because this file says so. Nobody is watching, so a session owes it
four things:

- **A question goes to the proxy; only an escalation is a `blocked`.** There is
  no one to answer "which do you want?". Stage 2 that needs a decision (a seam
  the ticket does not name, a blank the spec left) asks the proxy first — see
  "Asking the proxy" below. Only when the proxy escalates, or no proxy exists,
  does it touch nothing, set `Stage: blocked` with the question under
  `## Comments`, commit, and stop. Stage 3 that is unsure writes `Needs your
  call` and finishes; it never ends at `reviewing` asking what to do.
- **Nothing in the background.** A headless session ends when its turn does, and
  a gate or build left running in the background dies with it, unread. Run every
  command in the foreground and read its result before the next step.
  Measured 2026-09-24: a PHY-23 review backgrounded the gate and ended at
  `to-review` two minutes in.
- **One stage per session.** Stage 2 stops the moment `to-review` is committed;
  it does not review its own work. Stage 3 stops at `done`, `to-merge`,
  `to-implement` or `blocked`, nothing else.
- **A failed attempt leaves a trace.** The driver writes `Attempt N failed:
  <reason>` under `## Comments`, committed on the branch. A session that finds
  one is a retry: read it first.

Answering is a stage-1 job, done once per batch: read the tree the driver prints
when it stops — every `blocked` node carries the question under it — then fold
each answer into the ticket body (Primary files, a criterion, a filled blank),
set `to-implement`, commit on the loop's base, run the driver again. Everything
else about the driver — the session branch, the run log, how to start it — is in
`sweatshop/SKILL.md`.

## Asking the proxy

The human stops the loop only for what the human alone can decide. Everything
else goes to the **proxy**: the `proxy` agent card (`agents/proxy.md` in this skills repo, linked as
`~/.claude/agents/`; its model and effort live only there),
a stand-in human on its own model. It holds in every stage and every session,
attended or not.

1. **Spawn it** with the ticket id, the question as you would have written it
   under `## Comments`, and the evidence you gathered (measurements, the options
   you tried). It answers `Decision: …` or `Escalate: …` on its first line.
2. **`Decision`**: record it under `## Comments` as `Proxy decided: <answer> —
   <its reason, one line>`. When the answer changes the contract, fold it into
   the body the way stage 1 would (Primary files, a criterion, a filled blank).
   Commit both with the next commit of the stage, then carry on as if the human
   had answered.
3. **`Escalate`**: the old path. `Stage: blocked`, the question and
   `Proxy escalated: <why>` under `## Comments`, commit, stop.
4. **No card, or a runtime that cannot spawn one** (Codex): the old path, with
   no proxy line.

**Only an actual proxy answer earns `Proxy decided`.** The proxy is read-only
and returns decision/draft text. The caller owns repository edits and commits,
including copying that answer with its reason and attribution. A session's own judgement goes under
`## Comments` in its own voice, and a session without a proxy asks by stopping.
Measured 2026-09-30: a Codex stage 2 (PHY-43) wrote two `Proxy decided` lines
for decisions no proxy had made.

The proxy escalates only when there is no way forward without the human, or a
wrong answer is irreversible or expensive to undo. Stage 3 names every `Proxy
decided` line of the ticket in its findings and records the disclosure above,
so the session PR shows the answer, evidence and integration/release impact.

## A repo with no bindings block

Ask for the three values, write the block where it belongs, then get on with the
work. Do not copy this skill into the repo — one copy of the standard is the point.

    ## Bindings do fluxo (skill `ticket-flow`)

    - Gate: `<command that runs typecheck + lint + tests>`
    - Base branch: `<name>`
    - Models: stage 1 <model>, stage 2 <model> [effort], stage 3 <model> [effort]
    - Models (<lineup>): stage 2 <model> [effort], hard <model> [effort], stage 3 <model> [effort]

Cada linha `Models` é uma lineup. `Models:` (ou `Models (Claude):`) é a padrão do
driver; `Models (<nome>):` é escolhida com `-Lineup <nome>`, e `Models (Codex):` é
a do `sweatshop-codex.ps1`. O runtime segue o modelo, estágio por estágio (`gpt-*`
roda no Codex, o resto no Claude Code), então uma lineup pode misturar os dois.
Modelo Claude sempre com versão (`opus-5.5`, `sonnet-5`, `fable-5.1`; `opus 5.5`
também serve): o driver recusa `opus` sozinho. Inclua só as lineups que o repo
usa. O `[effort]` é opcional; sem ele, `high`.

`hard` é o implementador dos tickets `Difficulty: hard` e dos que já reabriram
duas vezes; sem ele, o stage 2 implementa todos. Só o implementador muda: o
revisor da lineup tem que bastar para qualquer ticket. O revisor mais caro fica
para o PR `Review: human` e para as auditorias antes de release.

Tracker paths and ticket shape do **not** go in this block. They are already in
`docs/agents/issue-tracker.md`.
