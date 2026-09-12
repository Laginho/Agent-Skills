---
name: ticket-flow
description: The one-ticket-at-a-time build loop — stage 1 specifies, stage 2 implements test-first, stage 3 reviews and merges. Use when a session receives a bare ticket ID, or when asked to run a stage of the ticket flow.
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
| 1 | `grill-me` → `to-spec` → `to-tickets` | `spec.md` + one ticket file per ticket, `Stage: to-implement` | the human does not approve the seams or the slicing |
| 2 | `tdd` | branch named for the id, `Stage: implementing`; **a test-only commit, red for the right reason**; then code commits that do not touch tests; gate green; `Stage: to-review` | the ticket needs more than one seam (back to stage 1), or a test proves wrong after being committed (`Stage: blocked` + reason) |
| 3 | `code-review` (Standards + Spec axes) | small fixes; then either merge, or a PR that waits | a finding is large — reopen the ticket, back to stage 2 |

Stage 1 also registers new ids in the repo's plan document, if it has one, at the
position of the original. That is the only edit anyone makes to the plan.

Refactoring outside what the ticket touched is not part of any stage. It becomes
its own `CLEAN-*` ticket.

Two overrides on the skills the stages call:

- **Stage 2 does not re-negotiate seams.** The `tdd` skill writes no test at a
  seam the user has not confirmed; here the ticket *is* that confirmation — its
  Primary files and its "Tests stage 2 writes" section name the seams, approved
  when the human approved the ticket. Stop only if the ticket needs a seam it
  does not name, which is the back-to-stage-1 case.
- **Nobody refactors mid-loop.** `tdd` parks refactoring in the review stage; the
  review parks anything outside the ticket's Primary files in a `CLEAN-*` ticket.

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
| → `to-merge` | stage 3 | the commit the PR is opened from |
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

Four additions, and each earns its place:

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
  play, never an implementation plan.
- **Numbered criteria**, not checkboxes, so a review can fail "criterion 5" by name.

Also per effort directory: `ledger.md`, a `| Data | ID | Commit |` table of closed
tickets, one line each, written when a ticket reaches `done`.

## Dispatch on a bare ID

A session handed nothing but an id (`OBS-004`) finds the ticket — the tracker file
says how, usually `grep -rl '<ID>' <tracker path>` — and dispatches on `Stage`.

**Find the branch before reading `Stage`.** The stage is committed on the
ticket's branch (stage 2 names it after the id, lowercased: `obs-004`). The copy
on the base branch is stale until merge, so a fresh session on `master` reads
`to-implement` on a ticket that is actually waiting for review. Run
`git branch --list '<id lowercased>'` first; if the branch exists and is not
merged into the base branch, check it out and read the ticket there. Only then
dispatch:

| Stage | What you do |
|---|---|
| `to-implement` | Stage 2. Call the `tdd` skill. |
| `implementing` | A session stopped mid-run. Report what the branch holds and stop — do not continue blind. |
| `to-review` | Stage 3. Call the `code-review` skill. |
| `reviewing` | Same as `implementing`: report and stop. |
| `to-merge` | The PR waits on the human. Report it and stop. |
| `done` | Nothing to do. Say so and stop. |
| `blocked` | Report the reason from `## Comments` and stop. |

Three guards:

- **`to-implement` with an unmerged branch is a stale read.** You skipped the
  branch check above. Check the branch out and dispatch again.
- **Wrong model, no work.** If the bindings assign that stage to a model you are
  not, say which stage the ticket wants and which model owns it, then stop.
- **Reopened tickets look new.** `Stage: to-implement` on a ticket that carries a
  stage-3 review section means only the ❌ items are left, and the work continues
  on the existing branch. Read the ticket to the bottom before starting.

## The rules that hold the loop up

**Tests go in their own commit, red, before any code.** The load-bearing check is
the `diff --stat` separation, not any agent's promise. Whoever writes the tests
does not make them pass in the same commit, and stage 2 does not touch test files
in a code commit. This rule exists because green tests have sat on top of a broken
parser — the tests were exercising a copy of the logic.

**Primary files and the numbered criteria are the contract.** Stage 2 reads those
two lists and treats them as binding. A requirement stated only in prose is
invisible: it gets met by accident or not at all.

**Small fix, or back to stage 2 — decided mechanically.** A fix is small if it
fits inside the ticket's Primary files *and* needs no new test. If it needs a new
test, or touches source outside the Primary files, stage 3 does not fix it:
reopen, back to stage 2. No exceptions — a reviewer judging size by feel will
always find its own findings small.

**A finding that belongs to another ticket goes under `## Comments` on that
ticket — never into its body.** Only stage 1 moves a comment into the body, and
when it does it adds the file to Primary files and a numbered criterion. An
unfolded comment is a note, not a requirement: prose in a body that no file and no
criterion backs is invisible to stage 2, which will ship green without it.

**Red-green proof before reporting.** Show that the new tests fail without the
change and pass with it. Report the real suite counts, not rounded ones. Every bug
fix has a test that would fail without it, and that test calls production code,
never a copy of it.

**Reopening.** A review that knocks down a closed ticket sets
`Stage: to-implement`, marks which criterion fell (❌ with the reason), removes the
ledger line, and appends a review block saying what is left.

## Commits and closing

Conventional Commits in English, the body saying why and citing the id
(`fix: ... (BUG-003)`). Never squash.

Stage 3 closes by appending a `#### Resolution (YYYY-MM-DD)` block to the ticket —
decision, files, red-green proof, gate output — and adding the ledger line, in the
same commit as `Stage: done`. **The ticket is the memory between sessions.**

Merge: if stage 3 changed no code, it merges directly and sets `done`. If it
changed code, it opens the PR, sets `to-merge`, and stops.

## A repo with no bindings block

Ask for the three values, write the block where it belongs, then get on with the
work. Do not copy this skill into the repo — one copy of the standard is the point.

    ## Bindings do fluxo (skill `ticket-flow`)

    - Gate: `<command that runs typecheck + lint + tests>`
    - Base branch: `<name>`
    - Models: stage 1 <model>, stage 2 <model>, stage 3 <model>

Tracker paths and ticket shape do **not** go in this block. They are already in
`docs/agents/issue-tracker.md`.
