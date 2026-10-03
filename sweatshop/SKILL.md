---
name: sweatshop
description: The unattended ticket-flow driver — runs fresh Claude Code or Codex CLI sessions, one stage at a time, and collects merged tickets in one session PR. Use when asked to start the driver ("roda o loop", "start the unattended run", "/sweatshop"), or to explain its run log or PR.
---

# Sweatshop

`scripts/sweatshop.ps1 <repo> [-Lineup <name>]` runs the lineup's models: each
stage on the runtime its model belongs to (`gpt-*` on Codex, the rest on Claude
Code), so a lineup may pair a Codex implementer with a Claude reviewer.
`scripts/sweatshop-codex.ps1 <repo>` is `-Lineup Codex`. It sends bare ids into a fresh CLI session, one stage at a
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
   Stage 2 runs on the lineup's `hard` model instead of its `stage 2` one when
   the ticket says `Difficulty: hard` or carries two `Verdict: Reopen` lines;
   the run log's `Model` column shows which one ran. The reviewer never changes.
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

- `<tracker>/run-log.md`: one row per **stage run** — when, id, stage, model
  with its effort (`sonnet-5 xhigh`), attempt, outcome, session, minutes, tokens, cost. One row per ticket would collapse stage 2
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
  after the second, or at once when the session ended on a question or committed `blocked` itself (its whole last message is kept). A stage
  that asked keeps its commits: the driver renames its branch to
  `<branch>-asked-<yyyymmdd-hhmm>` and names it in the note, so the answer can
  resume from it while the next stage 2 still starts clean. An API outage
  spends no attempt; two in a row stop the run. A usage limit that names its
  reset time (`try again at 1:38 PM`) is waited out instead. A refused request
  (a 400 `invalid_request_error`, such as a CLI too old for its model) stops the
  run at once, since a retry sends the same request: update the CLI, relaunch.

Both log paths are in `.git/info/exclude`: local, never in a commit.

`scripts/scoreboard.ps1 <repo> [<repo>...]` reads those logs across repos and
prints two tables: one per implementer (stage runs, failed and asked attempts,
median minutes, cost), and the reopen rate per implementer → reviewer pair. Each
review is charged to whoever last sent the ticket to review. It reads files only;
`-SelfCheck` tests the attribution.

It prints the open tickets as a tree before and after every run, including runs
it refuses and runs that crash. `/standup` renders the same tree for where things
stand now; the log is what happened while nobody watched.

## Starting one

Asked to start the driver, find the script next to this file — the user should
never have to. In Claude Code run `scripts/sweatshop.ps1`; in Codex run
`scripts/sweatshop-codex.ps1`. Resolve it from where this file was loaded; one
recursive search from the skills directory if needed. Never select the runtime
from which CLIs happen to be installed: both can be installed on one machine.

The target repo's `## Bindings do fluxo` block supplies the lineups, one
`Models` line each. With no `-Lineup` the driver reads `Models (Claude):`, else
`Models:`; `-Lineup night` reads `Models (night):` and never falls back. The
driver refuses a missing line instead of guessing a model. Choosing the lineup:

- The user names a binding line ("the night lineup", "nightshift"): `-Lineup night`.
- The user spells out models ("luna max implements, opus 5.5 reviews"): pass them
  for this run only, in the binding's syntax:
  `-Models 'stage 2 gpt-6-luna max, stage 3 opus-5.5 high'`.
- Neither: no flag, the default line.

Never edit the binding to run a lineup. The edit dirties the tree Preflight wants
clean, and it changes the repo's default for every later run. A lineup worth
keeping goes into the binding by a commit the user asked for.

Claude models carry their version (`opus-5.5`, `sonnet-5`, `fable-5.1`,
`haiku-4.5`; `opus 5.5` reads the same). An unversioned `opus` is refused: an
alias moves when a new model ships, and the lineup would change unannounced. For
example:

    - Models: stage 1 opus-5.5, stage 2 sonnet-5 high, hard opus-5.5 high, stage 3 opus-5.5 high
    - Models (Codex): stage 1 gpt-6-sol, stage 2 gpt-6-luna high, stage 3 gpt-6-sol high
    - Models (night): stage 2 gpt-6-luna max, stage 3 opus-5.5 high

A mixed lineup needs both CLIs installed and logged in; the driver checks at start.

Codex stages run with `--approve-for-me`: the workspace-write sandbox, with
every escalation judged by Codex's automatic reviewer instead of a human. On
Windows the sandbox keeps `.git` read-only and cannot reach the keyring, so git
and gh fail once and run on the approved retry.

The repo is the current one when its `AGENTS.md` carries the `## Bindings do
fluxo` block; otherwise ask which. When asked to run, launch the selected script
and show where its output lands. These are the corresponding commands:

    & "<skills-dir>\sweatshop\scripts\sweatshop.ps1" "<repo>"
    & "<skills-dir>\sweatshop\scripts\sweatshop.ps1" "<repo>" -Lineup night
    & "<skills-dir>\sweatshop\scripts\sweatshop.ps1" "<repo>" -Models 'stage 2 gpt-6-luna max, stage 3 opus-5.5 high'
    & "<skills-dir>\sweatshop\scripts\sweatshop-codex.ps1" "<repo>"

Runs on different repos can go in parallel, one session each; a second run on a
repo that already has one is refused.

Run it in a background terminal/session: a foreground tool call can time out
before a stage ends. Say where the output lands and end the turn. Do not poll
unless running `foreman`, which owns the watching.

To pause a run, create `<tracker>/run-log/STOP`. The driver deletes it and ends
between stages through its normal end: tree reset, session PR published, back on
the base. Killing the process skips that end and can leave a stage half-written.

The process belongs to the session that launched it. If that session dies,
Preflight may find a ticket at `implementing` and refuse the next run. A terminal
the user owns can outlive the agent session; give them the line above when they
ask to launch it themselves.

Offer `-DryRun` (prints the tree, the session it would use and the first command;
touches nothing) the first time a repo runs the loop, and `-SelfCheck` if the
script itself looks wrong.
