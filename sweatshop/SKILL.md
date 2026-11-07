---
name: sweatshop
description: The unattended ticket-flow driver — runs fresh Claude Code, Codex or OpenCode CLI sessions, one stage at a time, and collects merged tickets in one session PR. Use when asked to start the driver ("roda o loop", "start the unattended run", "/sweatshop"), or to explain its run log or PR.
---

# Sweatshop

`scripts/sweatshop.ps1 <repo> [-Lineup <name>]` runs the lineup's models: each
stage on the runtime its model belongs to (`provider/model` on OpenCode, `gpt-*`
on Codex, the rest on Claude Code), so a lineup may pair a Codex implementer with
a Claude reviewer. `scripts/sweatshop-codex.ps1 <repo>` is `-Lineup sol`. It sends
bare ids into a fresh CLI session, one stage at a time, then reads `Stage:` back.
**The driver adds no instructions of its own.** Everything a session does, it does because
`ticket-flow/SKILL.md` says so; this file owns only the driver.

## What one run does

1. **Updates itself.** `git pull --ff-only` in the repo this skill lives in. A
   pull that fails stops the run: a driver stale on one machine and fresh on the
   other is the bug this step kills. A changed revision reparses the entry point once.
2. **Preflight.** Clean tree, on the bindings' base branch, base pulled, no
   ticket left `implementing` or `reviewing` by a run that died. Before the first
   stage it pings the proxy (see The proxy); no answer stops the run.
3. **Picks the session.** A `sweatshop/*` branch not merged into the base —
   local or remote — is reused. None: `sweatshop/<yyyy-mm-dd>` is created from
   the base and pushed. It is checked out, and from here it is the loop's base:
   stage 2 branches from it, stage 3 merges into it. Every session `ticket-flow`
   spawns finds it the same way, by name, so the driver never has to say so.
   With `-Lane`, only `sweatshop/<lane>/*` counts (see Lanes).
4. **Runs tickets** until nothing is runnable: `to-review` first, then any
   `to-implement` whose `Blocked by` are all `done` — `done` on the session, so
   dependents start on top of what they depend on, no human merge in between.
   A `Blocked by` that names no ticket on the session is parked `blocked`
   before the first stage. Stage 2 runs on the lineup's `hard` model instead of its
   `stage 2` one when the ticket says `Difficulty: hard` or carries two
   `Verdict: Reopen` lines (the run log's `Model` column shows which ran). After the
   second reopen, park that ticket for the foreman's cause diagnosis before another
   attempt; other runnable tickets continue. The reviewer never changes. A grown
   `Progresso: <k> de <M>` (`ticket-flow`, partial handoff) logs `progress k/M` and
   spends no attempt.
5. **Stops and reports.** Prints the open tree, then pushes the session and
   opens its PR against the base — or updates the body if the PR exists — and
   returns to the base branch.

The session lives until its PR is merged. Answer the `blocked` questions, run
again: same branch, same PR, more tickets. Merge the PR and the next run starts a
new session, because the old one is now merged and the search skips it.

## The session PR

Titled `<repo>: <session branch>` with slashes as spaces (`Agent-Skills: sweatshop
2026-10-29-1430`), so an inbox of several projects' PRs says which is which.

One line per ticket that reached `done` on the session — id, `Review:`, verdict
— `Needs your call` and `Review: human` at the top, `Approve` from `Review: agent`
below: open the PR, read from the top. The body also carries proxy decisions,
pending product acceptance and known deferred defects with their release impact.
`Approve` is implementation approval; missing legacy acceptance is unknown. A
ticket going from non-done to done (a reopen cycle included) counts as completed;
old done tickets with comment edits are disclosure context only.

Edit on the branch if something needs fixing, then merge. Nothing flows back to
the tickets; the PR is the record. A ticket you disagree with is reopened the
way `ticket-flow` already says (`Stage: to-implement`, ❌ on the criterion). An
edit big enough to matter is a `CLEAN-*` ticket, not a retrofit.

The base moving while a session is open is not the driver's problem: with lanes
the foreman syncs the session (`foreman`, section 9); the rest is the human's call.

## The proxy

One stand-in human for every runtime: the card `proxy.md` beside this file, on
the model its `model:` line names (any runtime's id; Claude ids pinned). Every
caller, attended or not, reaches it through `scripts/proxy.ps1`, which runs that
model's CLI read-only, prints the answer and the `Proxy decided (<model>)` or
`Proxy escalated (<model>)` line to record, and writes a receipt under
`sweatshop-proxy` in the temp folder. Changing the proxy's model is editing those two
lines; Claude ids are pinned to a version.

- **Pings, before the first stage.** `proxy.ps1 -Ping` must answer
  `Decision: pong`, or the run stops. Then each runtime in the lineup runs the same
  ping from inside its harness. A receipt means that runtime's stages call the proxy
  themselves; none means they cannot (inside the Codex sandbox a nested `claude`
  call hangs), so they run with `SWEATSHOP_PROXY=driver`, where `proxy.ps1` fails at
  once and the stage stops with its question. The `.out` says which: `proxy from
  <runtime> sessions: reached directly | unreachable`.
- **The driver answers a stage that asked.** A stage 2 that ends `blocked` or on a
  question, with no `Proxy escalated` line of its own, has its question put to the
  proxy by the driver. A `Decision` is recorded under `## Comments` with the whole
  answer quoted, and the ticket goes back to `to-implement`; an `Escalate` is
  recorded and the ticket stays `blocked`. Twice per ticket per run; a third ask
  waits for the human.
- **Receipts are checked:** a `Proxy decided` or `Proxy escalated` line without a
  receipt for that ticket and model parks the handoff.

## What the driver writes

- `<tracker>/run-log.md`: one row per **stage run** — when, id, stage, model
  with its effort (`sonnet-5 xhigh`), attempt, outcome, session, minutes, tokens, cost, and sampled runtime-completion to process-exit
  `Shutdown s` (`?` when unmeasured). Stage rows, not ticket rows, so stage 2 and
  stage 3 keep their own duration and model. The aggregate line printed at the end
  is the trigger to investigate, not the investigation.
- **Cost** is USD at API list price, the one measure both runtimes give; hold it
  against the plan's price. Claude prices its own session (`total_cost_usd`,
  subagents included). Codex reports tokens only; the driver prices them from
  `$CodexPrices` in the script, at short-context rates, so a long-context stage
  reads low. A model missing from that table logs `?`, never a guess: add its row
  from OpenAI's pricing page. A Codex stage's cost includes its subagent rollouts,
  and a stage killed by time is priced from its rollout as a lower bound.
- **The dashboard** (`dashboard/`, a Cloudflare Worker and D1 table): with
  `SWEATSHOP_DASH_URL` and `SWEATSHOP_DASH_TOKEN` set, the driver posts its lane's
  snapshot and a heartbeat (shape and intervals in `dashboard/worker.js`; a lane
  silent for 10 minutes reads `no heartbeat`). The page shows only running and
  crashed lanes. Either variable unset turns it off; the run's first lines say
  `dashboard: off` or `dashboard: reporting to <host>`. A failed post never stops
  the run. `SWEATSHOP_FOREMAN` is the card's tag (unset: `manual`). Reading is
  public: anyone with the URL sees ticket titles and costs. Deploy with
  `npx wrangler deploy` from `dashboard/`, then `dashboard/smoke.ps1`.
- `<tracker>/run-log/<id>-<stage>-<when>.txt`: the session's full output (for
  Claude, its JSON result); `.final` holds its last message, `.runtime.json` the
  start, completion, exit, forced cleanup and infrastructure errors, `.row.txt` the
  outcome saved before the cumulative append. A failed append stops between stages
  and leaves its row for the foreman to reconcile.
- Each CLI launches suspended into its own Windows Job Object before running.
  Normal exit, a ten-second grace after a terminal runtime event, or the stage
  time limit (below) closes that job and its descendants. On Linux (`pwsh` 7) the job is a
  transient systemd user scope capped at 6 GB of RAM and 1 GB of swap (a runaway gate is
  OOM-killed inside it, not the desktop session): its cgroup keeps descendants that start a new
  session (Codex does, per tool command), they get SIGTERM, then `cgroup.kill`
  after 3 s, and a watchdog in the scope kills it if the driver dies. A Linux
  driver therefore needs a systemd user session (`systemd-run --user`). Existing shared services are not
  owned by it. Broker-launched processes outside the job need explicit ownership
  and cleanup in their QA kit. Committed ticket state decides success; a final
  message or terminal event alone does not. Log reads retry sharing violations
  briefly; unavailable evidence parks the ticket as an infrastructure failure.
- Before resetting dirty work, stash tracked/untracked edits under
  `refs/sweatshop-recovery/` and append the reference to `run-log/recovery.txt`.
  Recovery refs are outside ticket branch discovery. The foreman inspects them before retrying.
- **A retry resumes.** A stage 2 that stopped short of `to-review` keeps its
  branch. If the branch says `implementing` (stage 3's: `reviewing`), the driver
  commits it back to `to-implement` (`to-review`) on that branch, unpushed, with a
  `Driver retry: <why>` note, so the next session resumes instead of stopping on a
  stage found mid-run.
- **The time limit is a backstop for hangs.** `-ImplementMinutes` and
  `-ReviewMinutes` default to 240: a gate alone takes 40–60 min on a loaded Linux
  notebook, and a shorter limit spent attempts on real work. Pass other values for
  one run. A stage the limit kills spends no attempt and writes no `Attempt N
  failed`: its row says `timeout, not counted`, its edits are saved as above, and
  the ticket runs again from its branch. Two timeouts in a row on one ticket (one
  run) park it: row `timeout, parked`, `Stage: blocked` on the session with a
  `Stage stopped (timeout)` note for the foreman, branch already resumable.
- Under `## Comments` of a ticket, committed on the session: `Attempt N failed:
  <reason>` after a stage 2 that did not reach `to-review` for any other reason; `Stage: blocked`
  after the second, or at once when the session ended on a question or committed `blocked` itself (its whole last message is kept). A stage
  that asked keeps its commits: the driver renames its branch to
  `recovery/asked/<yyyymmdd-hhmmss>/<ID>` and names it in the note, so the answer can
  resume from it while the next stage 2 still starts clean. An API outage
  spends no attempt; two in a row stop the run. A usage limit that names its
  reset time is waited out instead. A refused request (a 400
  `invalid_request_error`) stops the run at once, since a retry sends the same
  request: update the CLI, relaunch.

Both log paths are in `.git/info/exclude`: local, never in a commit. Active branch
discovery uses `scripts/ticket-state.ps1`, shared with dispatch and standup.
Ambiguity, unmerged `done` and missing/stale gate evidence cannot unlock
dependents. A bad stage handoff is parked with its work retained, rather than
reported as merged; two more park the same way: a stage-2 commit that touches both
test files and production (test paths, plus the binding's optional `Test files:`
regex for fixtures kept beside production; the tracker counts as neither), and a
proxy line without a matching receipt.

`scripts/scoreboard.ps1 <repo> [<repo>...]` reads those logs across repos and
prints a table per implementer and the reopen rate per implementer → reviewer pair
(each review is charged to whoever last sent the ticket to review); its header
describes the findings table. `interventions.md` separates rescues from routine
approvals, proxy decisions and automatic recovery. Unknown history stays unknown.

It prints the open tickets as a tree before and after every run, including runs
it refuses and runs that crash.

## Starting one

Asked to start the driver, find the script next to this file — the user should
never have to. In Claude Code or OpenCode run `scripts/sweatshop.ps1`; in Codex run
`scripts/sweatshop-codex.ps1`. Resolve it from where this file was loaded; one
recursive search from the skills directory if needed. Never select the runtime
from which CLIs happen to be installed: several can be installed on one machine.

The lineups are global: [`lineups.md`](lineups.md), beside this file, holds one
`Models (<name>)` line each for every repo. `Models (default): terra` names the
lineup a run with no `-Lineup` takes; `-Lineup opus` reads `Models (opus):` and
never falls back. The repo's `## Bindings do fluxo` block keeps only its own
values (gate, base branch); a `Models` line there is refused, so no repo carries
a stale copy. The driver refuses a missing lineup instead of guessing a model.
Choosing the lineup:

- The user names a lineup ("the opus lineup", "run it on opus"): `-Lineup opus`.
- The user spells out models ("luna max implements, opus 5.5 reviews"): pass them
  for this run only, in the lineup syntax:
  `-Models 'stage 2 gpt-6-luna max, stage 3 opus-5.5 high'`.
- Neither: no flag.

Never edit `lineups.md` to run a lineup: it changes the default for every repo and
every later run. A lineup worth keeping goes into `lineups.md` by a commit the
user asked for.

A Codex model may end in `fast` (`stage 2 gpt-6.1-sol high fast`): Codex's priority
tier (`service_tier=fast`), logged as `gpt-6.1-sol-fast`, its own scoreboard row,
priced at twice the base row. The response's `service_tier` echo reads `default`
even on fast; the proof is Codex's `RUST_LOG=codex_otel=info` line
(`service_tier="priority"`).

Claude models carry their version (`opus-5.5`, `sonnet-5`, `fable-5.1`,
`haiku-4.5`; `opus 5.5` reads the same). An unversioned `opus` is refused: an
alias moves when a new model ships. See `lineups.md` for the current lines.

A mixed lineup needs both CLIs installed and logged in; the driver checks at start.

Any model id with a slash runs on OpenCode, written as `opencode models` lists it
(`stage 2 opencode/big-pickle`), so any provider OpenCode reaches works with no
driver change. A reasoning variant rides in the id (`openai/gpt-6-sol#high`); the
effort word is not sent, because a variant the model lacks is refused. Each stage
runs in its own OpenCode server (so a timeout kill stops the agent), and `--auto`
approves every permission the OpenCode config does not deny. OpenCode reads no
global `CLAUDE.md`, so its prompt names the skill (`Use the ticket-flow skill on
<id>.`): `ticket-flow` and the skills it calls must be installed under
`~/.config/opencode/skills/` as junctions (symlinks on Linux) to this repo, never
copies, which go stale. The cost column is OpenCode's own price per step;
subagent sessions are not counted. An unknown model or variant stops the run
instead of retrying.

Codex stages run with `--dangerously-bypass-approvals-and-sandbox`: no sandbox
and no approvals, so run the driver only on a machine set aside for the runs (the
sandbox kept `.git` read-only and refused the gate's network and the proxy's
`systemd-run`).

The repo is the current one when its `AGENTS.md` carries the `## Bindings do
fluxo` block; otherwise ask which. When asked to run, launch the selected script
and show where its output lands. These are the corresponding commands:

    & "<skills-dir>\sweatshop\scripts\sweatshop.ps1" "<repo>" [-Lineup opus | -Models '<line>']
    & "<skills-dir>\sweatshop\scripts\sweatshop-codex.ps1" "<repo>"
    & "<skills-dir>\sweatshop\scripts\sweatshop.ps1" "<repo>\.artifacts-build\lanes\flutter" -Lane flutter

Runs on different repos can go in parallel, one session each. On one repo,
parallel runs are lanes.

## Lanes

`-Lane <folder>` names a tracker folder (`<tracker>/<folder>/issues`). The run
takes only that folder's tickets, on its own session `sweatshop/<folder>/<stamp>`
with its own PR. Blockers count as `done` from any folder, but only on the lane's
session: a ticket blocked by another lane's ticket waits until that lane's PR is
merged and this lane starts a new session. A blocker that is not on this lane's
session at all (published after it opened) parks the ticket `blocked` instead (4.).

- **One clone per lane**, of the same origin, made once and reused, in an ignored
  folder inside the repo, plus whatever the gate needs installed. For EasyMath:
  `git clone <origin url> .artifacts-build/lanes/<folder>`, then
  `npm --prefix app ci`. Pass the clone as `<repo>`. Two drivers on one checkout
  are refused, so the clone is what lets lanes share a repo. Its run log stays in
  the clone; the foreman merges it.
- **The clone starts from origin.** Push the base before starting lanes, or
  tickets committed only on the local base are missing.
- **Lanes should not edit the same files.** If they do, the later PR conflicts
  with the base; the foreman's sync resolves it or hands it to the human. Choosing
  lanes is planning, not the driver's job; one lane runs its tickets one at a time,
  so a chain that must stay serial stays in one lane.

Run it in a background terminal/session: a foreground tool call can time out
before a stage ends. Say where the output lands and end the turn. Do not poll
unless running `foreman`, which owns the watching.

To pause a run, create `<tracker>/run-log/STOP`. The driver deletes it and ends
between stages through its normal end: tree reset, session PR published, back on
the base. Killing the process skips that end and can leave a stage half-written.

The process belongs to the session that launched it; if that session dies,
Preflight may find a ticket at `implementing` and refuse the next run. A terminal
the user owns outlives the agent session: give them the line above on request.

Offer `-DryRun` the first time a repo runs the loop (a preview; local refs may
be stale, which it states). `scripts/check.ps1` runs the offline suite and never
launches a model.
