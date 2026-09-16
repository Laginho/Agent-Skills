---
name: sweatshop
description: The unattended driver for the ticket-flow loop — feeds ticket ids to claude one at a time, collects every merged ticket of a run on one session branch, and opens a single PR for the human. Use when asked to start the driver ("roda o loop", "start the unattended run", "/sweatshop"), or to explain the run log or the session PR.
---

# Sweatshop

`scripts/sweatshop.ps1 <repo>` runs the `ticket-flow` loop with nobody watching:
bare ids into `claude -p`, one stage per session, `Stage:` read back. **It adds
no instructions of its own.** Everything a session does, it does because
`ticket-flow/SKILL.md` says so; this file owns only the driver.

## What one run does

1. **Updates itself.** `git pull --ff-only` in the repo this skill lives in. A
   pull that fails stops the run — a driver that runs stale on one machine and
   fresh on the other is the bug this step exists to kill.
2. **Preflight.** Clean tree, on the bindings' base branch, base pulled, no
   ticket left `implementing` or `reviewing` by a run that died.
3. **Picks the session.** A `sweatshop/*` branch not merged into the base —
   local or remote — is reused. None: `sweatshop/<yyyy-mm-dd>` is created from
   the base and pushed. It is checked out, and from here it is the loop's base:
   stage 2 branches from it, stage 3 merges into it. Every session `ticket-flow`
   spawns finds it the same way, by name, so the driver never has to say so.
4. **Runs tickets** until nothing is runnable: `to-review` first, then any
   `to-implement` whose `Blocked by` are all `done` — `done` on the session, so
   dependents start on top of what they depend on, no human merge in between.
5. **Stops and reports.** Prints the open tree, then pushes the session and
   opens its PR against the base — or updates the body if the PR exists — and
   returns to the base branch.

The session lives until its PR is merged. Answer the `blocked` questions, run
again: same branch, same PR, more tickets. Merge the PR and the next run starts a
new session, because the old one is now merged and the search skips it.

## The session PR

One line per ticket that reached `done` on the session — id, `Review:`, verdict
— with the ones that want a human first: `Needs your call` and `Review: human`
at the top, `Approve` from `Review: agent` below. That order is the whole point:
open the PR, read from the top, stop when the lines turn boring.

Edit on the branch if something needs fixing, then merge. Nothing flows back to
the tickets; the PR is the record. A ticket you disagree with is reopened the
way `ticket-flow` already says (`Stage: to-implement`, ❌ on the criterion). An
edit big enough to matter is a `CLEAN-*` ticket, not a retrofit.

The base moving while a session is open is not the driver's problem: the session
meets it in the PR, and a conflict there is the human's call.

## What the driver writes

- `<tracker>/run-log.md`: one row per **stage run** — when, id, stage, model,
  attempt, outcome, session, minutes. One row per ticket would collapse stage 2
  and stage 3 into one duration and drop the model, the two axes worth
  correlating later ("tickets shaped like X cost sonnet three attempts").
  Nothing about the ticket is copied in; the ticket file is in git. The
  aggregate line printed at the end is the trigger to investigate, not the
  investigation.
- `<tracker>/run-log/<id>-<stage>-<when>.txt`: the session's full output.
- Under `## Comments` of a ticket, committed on the session: `Attempt N failed:
  <reason>` after a stage 2 that did not reach `to-review`; `Stage: blocked`
  after the second, or at once when the session ended on a question. An API
  outage spends no attempt; two in a row stop the run.

Both log paths are in `.git/info/exclude`: local, never in a commit.

It prints the open tickets as a tree before and after every run, including runs
it refuses and runs that crash. `/standup` renders the same tree for where things
stand now; the log is what happened while nobody watched.

## Starting one

Asked to start the driver, you find the script — the user should never have to.
It is `scripts/sweatshop.ps1` next to this file, under whatever directory the
tool installed the skill into (`~/.claude/skills/sweatshop/`,
`~/.agents/skills/sweatshop/`, …). Resolve it from where this file was loaded;
one recursive search for `sweatshop.ps1` from the skills directory if you do not
know that.

The repo is the current one when its `AGENTS.md` carries the `## Bindings do
fluxo` block; otherwise ask which. Then hand over one copy-ready line, or launch
it yourself if the user would rather not watch it:

    & "<skills-dir>\sweatshop\scripts\sweatshop.ps1" "<repo>"

**Running it is fine — backgrounded, then stop.** A foreground call dies on the
tool's own timeout long before a 45-minute stage ends; a detached one does not.
Launch it detached, say where the output lands, and end the turn. Do not poll —
unless you are running the `foreman` skill, which owns the watching.

What that mode costs: the process belongs to the session that launched it. Close
the app mid-run and the stage dies with it, leaving a ticket `implementing` that
the next run's Preflight refuses until a human puts the stage back. So when the
user is at the keyboard, the line they run themselves is the better default —
their terminal shows the tree live and outlives any session.

Offer `-DryRun` (prints the tree, the session it would use and the first command;
touches nothing) the first time a repo runs the loop, and `-SelfCheck` if the
script itself looks wrong.
