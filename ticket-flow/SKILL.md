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
| 2 | `tdd` | branch named for the id, `Stage: implementing`; alternating **test-only commits, red for the right reason**, and production-only commits; gate evidence; `Stage: to-review` | the ticket needs more than one seam (back to stage 1), or a committed test proves the *contract* wrong — a criterion that cannot hold, a seam that does not exist (`Stage: blocked` + reason). Each stop is a question for the proxy first; `blocked` only on its `Escalate`, or when it cannot be reached ("Asking the proxy"). A test wrong only in its harness, or one asserting behaviour a criterion replaces, is not a stop (below) |
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
  does not name, which is the back-to-stage-1 case — and stopping starts with
  the proxy, attended or not: its `Decision` folds the answer in and stage 2
  carries on; only its `Escalate`, or a call that cannot reach it, sets `blocked`.
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
| → `to-review` | stage 2 | metadata handoff after the tested code commit, with valid green gate evidence |
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
  the ticket changes is in play. So are the tests that assert behaviour a
  criterion replaces: grep for them while writing the ticket and list them,
  marked test-only.
- **Numbered criteria**, not checkboxes, so a review can fail "criterion 5" by name.
  Each one satisfiable: before publishing, check every criterion against the
  others and against the physics or spec it rests on.
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
PR for the human. With no such branch, nothing below changes. Several open at
once are the driver's lanes (`sweatshop/<lane>/<stamp>`), which run side by side:
the loop's base is the one that is an ancestor of HEAD when the session starts
(`git merge-base --is-ancestor <session> HEAD`). The driver launches each stage on
its own session or on a ticket branch cut from it, and each session opens with its
own commit, so only one matches.

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
| `to-implement` | Stage 2. Read `stage2.md` beside this file, then call the `tdd` skill. |
| `implementing` | A session stopped mid-run. Report what the branch holds and stop — do not continue blind. |
| `to-review` | Stage 3. Read `stage3.md` beside this file, then call the `code-review` skill. |
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
  An attempt that stopped to ask leaves its branch as
  `recovery/asked/<when>/<ID>`, named in its `Attempt N stopped to ask` line:
  cut the ticket's branch from the session and bring those commits onto it
  before starting. A reopened ticket's last pass and review block are there.
## The rules that hold the loop up

Stage 2's rules are in `stage2.md` and stage 3's in `stage3.md`, beside this file;
each stage reads its own before it starts. These hold for both.

**Primary files and the numbered criteria are the contract.** Stage 2 reads those
two lists and treats them as binding. A requirement stated only in prose is
invisible: it gets met by accident or not at all.

## Commits and closing

Conventional Commits in English, the body saying why and citing the id
(`fix: ... (BUG-003)`). Never squash.

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

## Unattended runs

The `sweatshop` skill's driver feeds bare ids to fresh Claude Code or Codex CLI
sessions, one at a time, and reads `Stage:` back. It adds no instructions of its
own: everything a session
does, it does because this file says so. Nobody is watching, so a session owes it
four things:

- **A question goes to the proxy; only an escalation is a `blocked`.** There is
  no one to answer "which do you want?". Stage 2 that needs a decision (a seam
  the ticket does not name, a blank the spec left) asks the proxy first — see
  "Asking the proxy" below. Only when the proxy escalates or cannot be reached
  does it touch nothing, set `Stage: blocked` with the question under
  `## Comments`, commit, and stop. Stage 3 that is unsure writes `Needs your
  call` and finishes; it never ends at `reviewing` asking what to do.
- **Nothing in the background.** A headless session ends when its turn does, and
  a gate or build left running in the background dies with it, unread. Run every
  command in the foreground and read its result before the next step.

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
else goes to the **proxy**, a stand-in human: the card `sweatshop/proxy.md` in
this skills repo, on the model its `model:` line names. One proxy for every stage
and every runtime, attended or not, always through one script. Resolve
`sweatshop/scripts/proxy.ps1` from this skills installation and run it in the
foreground, through the Bash tool like the gate helper:

    powershell -NoProfile -File <proxy.ps1> -Repo <worktree> -Ticket <ID> -Question '<question>'

(`-QuestionFile <file>` for a long one.) Ask what you would have written under
`## Comments`: the criterion, the options you tried, the evidence (measurements,
the branch). The answer's first line is `Decision: …` or `Escalate: …`, and the
script ends by printing the line to record.

1. **`Decision`**: copy the printed `Proxy decided (<model>): … (receipt <path>)`
   line under `## Comments` as is, with the drafts of the answer after it. When the
   answer changes the contract, fold it into the body the way stage 1 would
   (Primary files, a criterion, a filled blank). Commit both with the next commit
   of the stage, then carry on as if the human had answered.
2. **`Escalate`**: copy the printed `Proxy escalated (<model>): …` line, set
   `Stage: blocked` with the question under `## Comments`, commit, stop.
3. **The script fails** (any exit but 0: this session cannot reach the proxy, or
   the call broke): set `Stage: blocked` with the question under `## Comments`,
   commit, stop. Under the driver, the driver puts the question to the proxy from
   outside the session and runs the stage again with the answer recorded.
   Attended, show the failure and ask the human.

**Only the script's line is a proxy line.** The driver checks every new
`Proxy decided` or `Proxy escalated` line against its receipt (this ticket, that
model) and parks the ticket when one does not match. Never write one yourself and
never play the proxy through a subagent: a decision of your own goes under
`## Comments` in your own voice.

**A `Proxy decided` the driver recorded** carries the proxy's whole answer quoted
under it. The next stage reads it as the human's answer: it folds a contract
change into the body the way stage 1 would, then works.

The proxy escalates only when there is no way forward without the human, or a
wrong answer is irreversible or expensive to undo. Stage 3 names every `Proxy
decided` line of the ticket in its findings, quoted in backticks or mid-sentence
(a bullet that starts with `Proxy decided` reads as a new record and needs a
receipt), and records the disclosure above, so the session PR shows the answer,
evidence and integration/release impact.

## A repo with no bindings block

Ask for the three values, write the block where it belongs, then get on with the
work. Do not copy this skill into the repo — one copy of the standard is the point.

    ## Bindings do fluxo (skill `ticket-flow`)

    - Gate: `<command that runs typecheck + lint + tests>`
    - Base branch: `<name>`
    - Models (default): <lineup>
    - Models (<lineup>): stage 2 <model> [effort], hard <model> [effort], stage 3 <model> [effort]
    - Test files: `<regex>`

Each `Models (<name>):` line is a lineup, chosen with `-Lineup <name>`.
`Models (default):` lists no models: it names the lineup the driver runs without
`-Lineup`. `sweatshop-codex.ps1` runs `-Lineup sol`. A repo with no `default`
falls back to the legacy `Models (Claude):`, then `Models:`. The runtime follows
the model, stage by stage (`gpt-*` runs in Codex, the rest in Claude Code), so
one lineup can mix both. Claude models always carry a version (`opus-5.5`,
`sonnet-5`, `fable-5.1`; `opus 5.5` also works): the driver refuses a bare
`opus`. Include only the lineups the repo uses. `[effort]` is optional; without
it, `high`.

`hard` is the implementer for `Difficulty: hard` tickets and for tickets that
have reopened twice; without it, stage 2 implements them all. Only the
implementer changes: the lineup's reviewer has to be enough for any ticket. The
more expensive reviewer is kept for the `Review: human` PR and for pre-release
audits.

`Test files:` is optional: a regex for test fixtures kept beside production code,
which a test-only commit may touch. The usual test paths need no line.

Tracker paths and ticket shape do **not** go in this block. They are already in
`docs/agents/issue-tracker.md`.
