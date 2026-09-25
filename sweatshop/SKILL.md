---
name: sweatshop
description: The unattended ticket-flow driver — runs fresh Claude Code or Codex CLI sessions, one stage at a time, and collects merged tickets in one session PR. Use when asked to start the driver ("roda o loop", "start the unattended run", "/sweatshop"), or to explain its run log or PR.
---

# Sweatshop

`scripts/sweatshop.ps1 <repo>` runs Claude Code;
`scripts/sweatshop-codex.ps1 <repo>` runs Codex. Each sends bare ids into a fresh CLI session, one stage at a
time, then reads `Stage:` back. **The driver adds
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
  attempt, outcome, session, minutes, tokens, cost. One row per ticket would collapse stage 2
  and stage 3 into one duration and drop the model, the two axes worth
  correlating later ("tickets shaped like X cost sonnet three attempts").
  Nothing about the ticket is copied in; the ticket file is in git. The
  aggregate line printed at the end is the trigger to investigate, not the
  investigation.
- **Cost** is USD at API list price, the one measure both runtimes give; no
  subscription bills it, it is what to hold against the plan's price. Claude
  prices its own session (`total_cost_usd`, subagents included). Codex reports
  tokens only; the driver prices them from `$CodexPrices` in the script, at
  short-context rates, so a long-context stage reads low. A model missing from
  that table logs `?`, never a guess: add its row from OpenAI's pricing page.
- `<tracker>/run-log/<id>-<stage>-<when>.txt`: the session's full output (for
  Claude, its JSON result). `.final` beside it holds the session's last message.
- Under `## Comments` of a ticket, committed on the session: `Attempt N failed:
  <reason>` after a stage 2 that did not reach `to-review`; `Stage: blocked`
  after the second, or at once when the session ended on a question or committed `blocked` itself (its whole last message is kept). An API
  outage spends no attempt; two in a row stop the run.

Both log paths are in `.git/info/exclude`: local, never in a commit.

It prints the open tickets as a tree before and after every run, including runs
it refuses and runs that crash. `/standup` renders the same tree for where things
stand now; the log is what happened while nobody watched.

## Starting one

Asked to start the driver, find the script next to this file — the user should
never have to. In Claude Code run `scripts/sweatshop.ps1`; in Codex run
`scripts/sweatshop-codex.ps1`. Resolve it from where this file was loaded; one
recursive search from the skills directory if needed. Never select the runtime
from which CLIs happen to be installed: both can be installed on one machine.

The target repo's `## Bindings do fluxo` block supplies models for each runtime.
`Models:` remains the Claude line for existing repos; `Models (Claude):` may
replace it. Codex requires `Models (Codex):`. The driver refuses a missing line
instead of guessing a model. For example:

    - Models: stage 1 opus, stage 2 sonnet high, stage 3 opus high
    - Models (Codex): stage 1 gpt-6-sol, stage 2 gpt-6-luna high, stage 3 gpt-6-sol high

Codex stages run with `--dangerously-bypass-approvals-and-sandbox`: on Windows
its sandbox keeps `.git` read-only and cannot reach the keyring, so a sandboxed
stage can neither commit nor push. Claude stages are held to a tool allowlist;
Codex stages are held only by `~/.codex/rules`. Say so before a first Codex run.

The repo is the current one when its `AGENTS.md` carries the `## Bindings do
fluxo` block; otherwise ask which. When asked to run, launch the selected script
and show where its output lands. These are the corresponding commands:

    & "<skills-dir>\sweatshop\scripts\sweatshop.ps1" "<repo>"
    & "<skills-dir>\sweatshop\scripts\sweatshop-codex.ps1" "<repo>"

Runs on different repos can go in parallel, one session each; a second run on a
repo that already has one is refused.

Run it in a background terminal/session: a foreground tool call can time out
before a stage ends. Say where the output lands and end the turn. Do not poll
unless running `foreman`, which owns the watching.

The process belongs to the session that launched it. If that session dies,
Preflight may find a ticket at `implementing` and refuse the next run. A terminal
the user owns can outlive the agent session; give them the line above when they
ask to launch it themselves.

Offer `-DryRun` (prints the tree, the session it would use and the first command;
touches nothing) the first time a repo runs the loop, and `-SelfCheck` if the
script itself looks wrong.
