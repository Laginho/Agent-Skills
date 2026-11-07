---
name: pr-review-loop
description: Use when asked to review PRs "until approved", to open a session per PR for review, or to run a review loop on one PR, like "roda o loop", "revise os prs abertos" or similar.
---

# PR review loop

Two entry points. **Fan-out** (the human names several PRs or "the open PRs"): run
section 1 in this session. **One PR** (a PR number and a worktree, usually handed down
by a fan-out): run section 2 and nothing else.

Read from the repo's `AGENTS.md` bindings, never guess: `PR gate:` (else `Gate:`),
`Base branch:`, `Worktrees:`. "The gate" below is that command. A `PR gate:` is the
fuller gate a repo runs only here, once per PR. The reviewer is the model the human names; else the **stage 3 model of
the default lineup** in the global `~/.claude/skills/sweatshop/lineups.md`
(`Models (default)` names the lineup; its `stage 3` entry is model and effort).
Pass the reviewer to `delegate_task` as a target with `options` (for Codex,
`{"reasoningEffort": "<effort>"}`); check the model id with
`orchestrator_capabilities` first.

The loop never merges and never pushes to the base branch. Approval hands the PR to
the human.

## 1. Fan-out

1. `git fetch --all --prune`; list the PRs (`gh pr list --state open --json number,headRefName,url`)
   or take the ones the human named. `link_pull_request` each one from this session.
2. One worktree per PR in the `Worktrees:` directory, on the PR's own branch:
   `git worktree add --track -b <head> <dir>/pr-<N> origin/<head>` (if the local
   branch exists, `git worktree add <dir>/pr-<N> <head>`).
3. One child per PR with `delegate_task` (child of this session, so it reports back;
   inherit this session's model), `clientRequestId` `pr-<N>-loop`. Task text:
   "Run the `pr-review-loop` skill, section 2, for PR #<N> (<url>), branch `<head>`,
   worktree `<absolute path>`." Add what the human said about scope, and any open
   tickets of that lane that are not findings of this PR.
4. End the turn: each child's completion wakes this session. Done when every child
   returned its report. Then give the
   human one table — PR, rounds, findings fixed / disputed / left as P3, what waits on
   them — and the merge order if two PRs touch the same files.

## 2. One PR

The whole loop is one turn: run as a child, the task ends when your turn ends, so
keep the turn open while a round or a gate is in flight. Work only in the given
worktree. Commit messages cite the PR (`(PR #<N>)`).

**Prepare.** `link_pull_request`; `git fetch origin`; if the branch is behind
`origin/<base>`, merge it in, so the gate covers what the merge will produce.
Conflicts in append-only records (run logs, interventions, attribution): keep both
sides' entries in order.
Gate the head (the merge, if there was one) before round 1, even when nothing was
merged: the PR gate covers tests no earlier gate ran. Red is a finding: fix it.

**Round k.** New `delegate_task` per round, reviewer target from the bindings,
`clientRequestId` `pr-<N>-review-r<k>`, `mode: "wait"`, `timeoutMs: 3600000`. On
`waitTimedOut`, keep the turn: poll `task_status` with a foreground wait between polls
(section 3). Never continue a round through the child's thread. The task text carries:

- The brief: integration review of `git diff origin/<base>...HEAD` in `<worktree>`;
  read `AGENTS.md`, `CONTEXT.md`, the decision records, and the lane's tickets and
  spec; check correctness, fidelity to the spec, test coverage of what changed, and
  what breaks for the app's users (accessibility included). Read-only: no edits,
  commits or pushes. Run only focused tests (one test file at a time), never the gate
  or a full suite: the machine is shared with other loops.
- The answer format: first line `VERDICT: APPROVED` or `VERDICT: CHANGES_REQUESTED`;
  then each finding with severity P0–P3, `file:line`, a concrete failure scenario,
  and the suggested fix.
- From round 2: every earlier finding, what happened to it (fixing commit, or the
  refutation with its evidence), and the objections still open. The scope narrows to
  `git diff <head round k-1 reviewed>..HEAD` plus those findings: code an earlier
  round already read yields a new finding only at P0–P1.
- Round 4, the last one: also ask whether the open findings share one cause in the
  PR's approach, and to name it as a single finding if they do.

**Each finding** ends fixed or refuted:
- Fix it and commit. Same defect elsewhere in the PR: fix those too.
- Refute it with evidence: a file, a test, a decision record, the ticket's own scope.
- A real gap outside this PR's scope: open a ticket in the tracker, shaped by `ticket-flow/ticket-shape.md` (next free ID across
  the base branch and every open session branch, since lanes number in parallel), and
  send the reviewer the ticket as the refutation.
- Taste or product calls (visual, tone, app scope): record and leave for the human.
  Pedagogy of draft content is the agents' call, grounded in the spec.

**Gate** after any change, through the lock (section 3), with the same binding. Green → `git push origin <head>`. Red on a
single timeout: rerun that test file alone; passing alone is load, so record it and go
on. Any other red: fix it.

Skip the gate when the change (a fix commit or a merge) touches only files no test
reads: prose docs (`docs/`, `*.md`) and the tracker (`.scratch/`). Push right away and
note "gate skipped: docs only" in the report. A test that loads a doc file, or any code,
config or fixture in the change: gate it.

**Stop** when the reviewer answers `VERDICT: APPROVED` with no P0–P2 open and the
last gate is green (or skipped as docs only) **for the current HEAD**: a commit after the approval (even a P3 fix) needs one more round. Also
stop when the same finding stays disputed for 3 rounds: report the disagreement. Round 4
is the cap: still not approved after it, stop and report what is open and the
reviewer's answer on the approach; the human decides whether it goes on.

**Report** to the parent, in the human's language: rounds; every finding with
severity and fate (commit / refutation / ticket / left to the human); commits pushed;
last gate (exit code, log path); what waits on the human (merge, P3s, decisions,
device or screen-reader checks nobody did).

## 3. Gate through the lock

Parallel loops share one machine, and concurrent gates exhaust its RAM.
[`scripts/gate-lock.ps1`](scripts/gate-lock.ps1) holds one of the machine's slots
while the gate runs and writes `WAIT`, `START`, the output, then `EXIT=<code>` to the log.

The turn must stay open (section 2), and a background task finishing does not wake it.
So: start the gate with Bash `run_in_background` (`timeout: 7200000`):

    powershell -NoProfile -File "<skill dir>\scripts\gate-lock.ps1" -Repo "<worktree>" -Log "<log outside the repo>" -Command "<PR gate: binding, else Gate:>"

(On Linux or macOS: `pwsh` instead of `powershell`, and `/` in the path.)

then wait in the foreground, in the same turn, until the log has `EXIT=`
(`until grep -q '^EXIT=' "<log>"; do sleep 10; done`, Bash `timeout: 600000`; repeat
the wait if it times out). Read the result by filtering the log; never rerun the gate
to change the filter.
