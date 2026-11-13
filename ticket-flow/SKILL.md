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
defined here and in `ticket-shape.md` — nowhere else.

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
| 2 | `tdd` | branch named for the id, `Stage: implementing`; alternating **test-only commits, red for the right reason**, and production-only commits; gate evidence; `Stage: to-review` | the ticket needs more than one seam (back to stage 1), or a committed test proves the *contract* wrong — a criterion that cannot hold, a seam that does not exist. Each stop goes to the proxy first ("Asking the proxy"). A test wrong only in its harness, or one asserting behaviour a criterion replaces, is not a stop (`stage2.md`) |
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
  does not name, which is the back-to-stage-1 case, and that goes to the
  proxy first.
- **Nobody refactors mid-loop.** `tdd` parks refactoring in the review stage; the
  review parks anything outside the ticket's Primary files in a `CLEAN-*` ticket,
  except documentation the change made stale, which it fixes (`stage3.md`).

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
| → `done` | stage 2 | the triage commit of a `wontfix` (`stage2.md`), on the loop's base |
| → `to-merge` | stage 3 | the commit the PR is opened from (no-session flow only) |
| → `to-implement` | stage 3 | the reopen commit |
| → `blocked` | anyone | with the reason under `## Comments` |

## Writing a ticket

Writing a ticket (stage 1, a review opening a follow-up, the foreman): use the shape in `ticket-shape.md`, beside this file. It replaces the `to-tickets` template and adds the id, `Primary files`, numbered criteria, `Review:`, `Difficulty:` and `Escaped-from:`; the `Stage:` line is above.

Also per effort directory: `ledger.md`, a `| Data | ID | Commit |` table of closed
tickets, one line each, written when a ticket reaches `done`.

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
driver: it excludes `recovery/*` and old `-asked-<time>` attempts, and stops on
ambiguous names or divergent local/origin copies. A local stage commit ahead of
origin is normal. To resume a remote ref, create its tracking local branch if
absent; fast-forward an existing local branch only when it is an ancestor.
Reconcile any divergence explicitly and preserve work.
Read committed ticket text from its unmerged branch, except `blocked` on the
loop's base wins. A merged branch uses the loop's base. An unmerged branch saying
`done` is an invalid handoff: preserve it and repair the merge or reopen; it does
not satisfy dependencies. Only then dispatch:

| Stage | What you do |
|---|---|
| `to-implement` | Stage 2. Read `stage2.md` beside this file, then call the `tdd` skill. |
| `implementing` | A session stopped mid-run, or another one is still on it. Report what the branch holds and stop — do not continue blind. The driver never leaves this for its own retries ("Unattended runs"). |
| `to-review` | Stage 3. Read `stage3.md` beside this file, then call the `code-review` skill. |
| `reviewing` | Same as `implementing`: report and stop. |
| `to-merge` | The PR waits on the human (no-session flow only). Report it and stop. |
| `done` | Nothing to do. Say so and stop. |
| `blocked` | Report the reason from `## Comments` and stop. |

Three guards:

- **Reconcile `to-implement` from the base with the committed branch.** The base
  copy may be stale: discover the active branch and read its Stage before
  dispatch. If that branch itself says `to-implement` after a reopen, a
  `Driver retry:` note or a `Progresso:` line (partial handoff, "Unattended runs"), stage 2
  resumes the retained work.
- **Wrong model, no work.** Inside a session branch (a `sweatshop/*` base, above), skip this guard:
  the driver picked your model, maybe from a lineup given only on its command
  line. Otherwise read every `Models (<lineup>):` line of the global
  `sweatshop/lineups.md` (beside this skill's folder). Each line is a lineup, and one lineup can mix runtimes,
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
Filter that log for counts/errors. Reuse its receipt when code is unchanged;
rerun only after changing code, never merely to produce paperwork. Append
`Gate evidence: <absolute JSON path>` to the ticket in the handoff commit, as
its own line starting with `Gate evidence:`, not a list item or comment bullet.
Between the tested commit and handoff only tracker tickets (this one, notes on
others, new ones) and feature ledgers may change; skills, scripts and other
documentation invalidate the receipt too.
The driver checks the receipt at `to-review`, `to-merge` and `done`; a missing or
stale one parks the ticket with preserved work. Logs and receipts are local
execution evidence; summarize/link durable verification in Resolution for another
machine's review.

## Unattended runs

The `sweatshop` driver feeds bare ids to fresh sessions, one at a time, and reads
`Stage:` back. Nobody is watching, so a session owes:

- **A question goes to the proxy; only an escalation is a `blocked`.** There is
  no one to answer "which do you want?": ask the proxy first ("Asking the
  proxy"), and set `Stage: blocked` only when it escalates or cannot be reached.
  Stage 3 that is unsure writes `Needs your call` and finishes; it never ends at
  `reviewing` asking what to do.
- **Nothing in the background.** A headless session ends when its turn does, and
  a gate or build left running in the background dies with it, unread. Run every
  command in the foreground and read its result before the next step.

- **One stage per session.** Stage 2 stops the moment `to-review` is committed;
  judging the work is stage 3's. Stage 3 stops at `done`, `to-merge`,
  `to-implement` or `blocked`, nothing else.
- **Stage 2 ends only at a handoff.** Its turn ends at `to-review`, at a
  `blocked` the proxy escalated, or, in a ticket split into parts, at a gated
  `Progresso:` part. A red test committed, part of the production written or
  "progress recorded in the ticket" is not one: nobody continues it, the
  driver counts the attempt as failed and parks the ticket after two. The
  stage has hours, not minutes; keep going until the handoff.
- **A retry resumes.** The driver writes `Attempt N failed: <reason>` under
  `## Comments`, and before retrying a stopped stage puts the branch's
  `implementing` back to `to-implement` (`reviewing` to `to-review`) with a
  `Driver retry: <why>` note. A session that finds either continues from the
  branch's commits; read what the last attempt proved before redoing it.
- **A ticket split into parts hands off one part per stage 2.** Only when the
  ticket says so (a repo rule such as one chapter per stage for a review that
  repairs several chapters): each stage does one part, gates it, commits it with
  `Progresso: capítulo <k> de <M>` on its own line of the ticket and `Stage:
  to-implement`, and stops. The next stage 2 resumes the branch at part k+1; the
  part that reaches M commits `to-review` instead, and stage 3 reviews every
  part at once.

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
   commit, stop. Attended, show the failure and ask the human.

**Only the script's line is a proxy line.** The driver parks a ticket whose new
`Proxy decided` or `Proxy escalated` line has no matching receipt. Never write one yourself and
never play the proxy through a subagent: a decision of your own goes under
`## Comments` in your own voice.

Stage 3 names every `Proxy
decided` line of the ticket in its findings, quoted in backticks or mid-sentence
(a bullet that starts with `Proxy decided` reads as a new record and needs a
receipt), and records the disclosure (`stage3.md`, Closing), so the session PR shows the answer,
evidence and integration/release impact.

## A repo with no bindings block

Read `bindings.md` beside this file and follow it.
