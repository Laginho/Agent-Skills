---
name: foreman
description: Runs a sweatshop run (or up to three lanes) with someone watching — launches the driver as a detached process, reads each finished stage, sends a heartbeat every 30 minutes, cleans up after a crash, and hands the human a summary at the end. Use when asked to "run the foreman", "supervise the sweatshop", "babysit the loop", or with /foreman.
---

# Foreman

You supervise one `sweatshop` run from this session. The driver still owns the
loop and `ticket-flow` still owns every stage; you own the watching. Read
`sweatshop/SKILL.md` first: it says where the driver is, what it writes and what
"finished" looks like.

Language follows `standup`'s rule.

**Lanes** (`sweatshop/SKILL.md`, Lanes): one foreman session watches up to
three lanes; split more across sessions, since every lane's stage reads fill the
same context. Each lane has its clone as `<repo>` and `-Lane <folder>` among the
flags. Everything below is per lane (notes file, watch, standup refusals,
summary, report, sync) except the clock: one check-in covers every lane, a line
each, and one watch loop polls every lane and exits on the first new line,
naming its lane. A lane that finishes gets sections 5 to 9 while the others keep
running; when the human merges one lane's PR, sync each other open lane
(section 9) once its driver stops. Make the clone first when it is missing, then
`<clone>/<tracker>/run-log/` before redirecting into it. `<tracker>` below is
the clone's, as an absolute path: the session's own folder stays the main
checkout, and two lanes resolving `.scratch/` there would share one notes file. The
standup refusals look at the lane only: a ticket at `implementing` in another
folder is another lane's run. `.artifacts-build/` is ignored, so a clean
`git status` on the main checkout says nothing about lanes running. Start every
chat line and push notification with the lane's name.

## 1. Standup, then launch

Run `/standup`. Stop here and say why when it shows any of: no unblocked
ticket, a dirty tree, a ticket at `implementing` or `reviewing`, or `blocked`
tickets waiting on the human and nothing else runnable. The driver's Preflight
would refuse the same things; you refuse them with the tree in view.

Then the base's CI: `gh run list --branch <base> --limit 3 --json conclusion,status,displayTitle,createdAt,url`.
Anything but `success` on the latest (a failure, or a job GitHub never started,
as when it refuses one for billing) goes in chat and the notes before launch,
and in the summary's **Your turn**: the session PR will merge into a base whose
remote gate is not running. It does not stop the launch.

Otherwise launch the runtime's driver (the script selected by `sweatshop`).
`SWEATSHOP_FOREMAN` is your tag on the dashboard's lane cards (`sweatshop/SKILL.md`,
What the driver writes): the name your prompt gives you, else `foreman <lanes>`
(`foreman a+b`). In Claude Code, launch it as a **detached process** with its
output in a file:

    $env:SWEATSHOP_FOREMAN = '<name>'; Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','<script>','<repo>',<flags> -RedirectStandardOutput <tracker>/run-log/driver-<when>.out -RedirectStandardError <tracker>/run-log/driver-<when>.out.err -WindowStyle Hidden -PassThru

On Linux, from Bash (there `Start-Process` pipes the output through the launching
shell, so it stops when that shell exits); its pid is `pgrep -f '<script> <repo>'`.
The first line loads the dashboard's settings, which a non-interactive shell never
reads from `~/.bashrc`:

    [ -f ~/.sweatshop-dashboard.env ] && { set -a; . ~/.sweatshop-dashboard.env; set +a; }
    SWEATSHOP_FOREMAN='<name>' setsid systemd-run --user --scope --collect --unit=sweatshop-driver-<lane>-<when> pwsh -NoProfile -File <script> <repo> <flags> > <tracker>/run-log/driver-<when>.out 2> <tracker>/run-log/driver-<when>.out.err < /dev/null &

The scope is what outlives the session: T3 Code kills the session's whole cgroup
on stop, and `setsid` alone does not leave it. `cat /proc/<pid>/cgroup` must name
the driver's own scope.

Not a background Bash/PowerShell task: those die at their `timeout`, 2 h at
most. The detached driver does not show in the session's task pane;
tell the human its pid and `.out` path. In Codex, a terminal session. A lineup the human asks for goes on the command line
(`-Lineup` or `-Models`, as `sweatshop/SKILL.md` says), never into `lineups.md`;
none asked for, run the default. A pause the human asks for is the driver's
`STOP` file (`sweatshop/SKILL.md`), never a kill. Note the
launch time and the last row of `<tracker>/run-log.md`: everything after that row
is this run. In Claude Code, the check-in clock is a background Bash
`sleep 1800` that you re-arm on every wake: its completion notice always wakes
you. Not `/loop` or a cron job, which can fail to fire with nobody noticing. In Codex, use a 30-minute thread heartbeat.

**A driver already running** (the human or another session launched it before
asking for you) is adopted, never relaunched: the standup's `implementing` ticket
is its stage, not a dead run. With no `.out` to poll, watch `<tracker>/run-log/`
for a new `<id>-<stage>-<when>.row.txt`, which the driver writes when each stage
ends. Its `throw` lands in the terminal it runs in: a check-in that finds no
growing stage `.txt` and no new row asks the human to look there. Note in the
notes file that the driver is adopted and where it runs.

**Keep notes in a file**, `<tracker>/run-log/foreman-notes.md` (excluded with the
rest of `run-log/`): one timestamped line per launch, stage row, cleanup, proxy
call and human request, then a `## Pending` list of what the run still owes. A
run outlives the session watching it, and the notes are what survives a restart. After a restart, read them first and resume from `## Pending`.

Never hold `<tracker>/run-log.md` open: on Windows a `tail -F` locks out the
driver's `Add-Content` and crashes its next row, and `TaskStop` leaves the lock
behind. Poll the driver's `.out` every 30 s instead, from a background loop that
exits on a new line (re-arm it each wake; it too dies at 2 h): it prints one line per finished stage
(`<id> <stage> (<model>): <outcome>, $<cost>`) and every `throw`.

## 2. Per stage, and the heartbeat

**Each finished stage** is a QA read, not a count. When the driver prints its
line, open that stage's `.final` (the session's last message) and check it
against the outcome: a `to-review` whose last message admits a skipped test, a
merge whose review raised something it then waved through, a `blocked` question
the proxy can answer (section 4). One line in chat and in the notes file: what
the stage did and anything that looks wrong.
**At the second reopen, diagnose before relaunching that ticket.** The driver
parks it as `blocked` and continues other tickets. Read both review blocks and
the intervening diff; record `Reopen diagnosis: <cause>; <next action>` under
`## Comments`, with evidence. A new implementation defect goes to stage 2; an
old defect missed by review gets one consolidated review of the affected paths
before the next implementation; a contract gap goes to stage 1/proxy; a regression
caused by review advice requires correcting that advice first. Causes can coexist.
Use the proxy for a contract decision as in section 4. Commit the diagnosis and
only then restore `to-implement` when the repair is concrete, on the session and
the retained ticket branch if it has a different Stage. Keep unresolved decisions
blocked. This diagnosis takes precedence over the generic blocked
question handling below.

**A `Stage stopped (timeout)` park is the foreman's call.** Read the two stage
logs: real progress (a gate still passing tests) means the machine is slow, so
raise `-ImplementMinutes`/`-ReviewMinutes` at the next launch; no output for long
stretches means a hang, so fix its cause first. Then restore the session's Stage
(`to-implement`, or `to-review` after a review); the ticket branch already reads
it, with its commits kept.

**The 30-minute check-in is a heartbeat**, for the human away from the screen.
Two sentences in chat, from two sources:

- **Finished**: rows appended to `run-log.md` since launch — id, stage, outcome.
- **Now**: the newest `<tracker>/run-log/<id>-<stage>-<when>.txt`. Its name is the
  ticket and stage; a growing file is a live stage.

    Finished A (merged) and B (to-review). Now reviewing C. All fine so far.

Add elapsed minutes on the current stage only when it exceeds the median for
that stage in `run-log.md`: that number is the one hint of a hang.

Every check-in reports, even when nothing moved: "Still implementing C, 12 min
in, nothing new" is the report. It goes in chat and as a push notification,
because the human is often away from the screen. The beep stays for trouble
only.

## 3. Crash

The driver's process is gone and its `.out` ends in a `throw` message, or a
check-in finds a `.err` file with content and no live `.txt`. Read the tail of
the stage's `.txt`, `.final` and `.err`, the driver's `.out` and `.out.err`, and `git -C <repo> status`.
Say what happened, then push-notify.

Read `<stage>.runtime.json` for completion, exit, forced cleanup and
infrastructure errors; the driver owns its job's cleanup, so leave shared
processes alone (process names are not ownership evidence).

Before resetting interrupted work, inspect `run-log/recovery.txt` and preserve
the refs and stashes listed there until recovery is verified. A driver killed before saving needs the same preservation **before**
checkout/reset: save HEAD under a new recovery ref, stash tracked and untracked
edits if present, retain the stash ref, and record both. Ignored runtime evidence
stays in `run-log/`; preserve any needed ignored project output separately.

- `implementing` (only a dead driver leaves it; its own retries reset the branch
  to `to-implement`): preserve the ticket branch under `recovery/<timestamp>/<id>`
  before removing its active name; record that branch in the ticket. The next
  stage inspects saved commits and tests to choose what to reuse, rather than
  continuing blind or discarding the attempt.
- `reviewing`: after preservation, restore `to-review` on the ticket branch and
  on the session if the driver parked it there; commit both.
- `<stage>.row.txt` is the outcome saved before appending to the cumulative log.
  If logging failed, append that row only if absent, under the matching header
  (including `Shutdown s`), before restarting. Keep the sidecar. Never reconstruct
  a successful outcome from the final message alone.

**Restart once**, detached again, when the cause is environmental:
API outage, network, `gh` or `git` transport, machine went to sleep. Any other
cause — a `throw` from Preflight, a script bug, the same stage failing twice —
you report and stop; a logic failure restarted is the same failure paid twice.
A usage limit is not a crash; the driver waits out one that names its reset time.
Only a limit without a time (a dated or weekly reset) still stops it.

## 4. Hands off

The human's calls stay the human's: questions the proxy escalated, the session
PR merge, any edit to code on the session branch other than section 9's sync. An edit you would have made is
a line in the summary, not a commit. No subagents: the proxy is
`sweatshop/scripts/proxy.ps1` (`ticket-flow`, "Asking the proxy").

**Push only the session branch and the base.** Never push a ticket branch, even
after committing a diagnosis on it: review rebases ticket branches locally, and a
stale `origin` copy makes the branch ambiguous to every reader (`~/.claude/hooks/no-ticket-push.py` refuses it where installed).

**A `blocked` ticket with no `Proxy escalated` line is not the human's yet.**
The driver already puts a stage's question to the proxy during the run; what is
left came from a third ask in one run, a proxy call that failed, or an older run.
Run `sweatshop/scripts/proxy.ps1` with the ticket id and a question built from
`## Comments` and the stage's `.txt`, plus the branch the driver kept for the
attempt (`recovery/asked/<when>/<ID>`, named
in the `Attempt N stopped to ask` line), so the answer can say "resume from it"
instead of starting over. Follow `ticket-flow`'s "Asking the proxy": record the
printed `Proxy decided` line (folded into the body when it changes the contract)
and set `to-implement`, or record the printed `Proxy escalated` line. Commit on
the session branch, then relaunch the driver once the run is over. A relaunch for proxy answers is not
the one restart of section 3.

## 5. Summary (when the task ends)

Stop the check-ins. Attribute reopened tickets, fixes made during review, and newly confirmed
post-approval findings first (section 6); when it owes a report (section 7), write and commit that next.

Every run, report or not, commits the run log. The driver keeps
`<tracker>/run-log.md` out of git on purpose (it resets the tree between
stages), so that file lives on one disk only, and it is what the scoreboard
compares models from. Merge it into `docs/run-log/run-log.md`, never copy over
it: the copy can hold rows another machine logged. Append this run's rows to the copy, then copy
the merged file back over the local log, so both disks start the next run with
the whole history. Commit the copy on the session branch and on the base branch,
both pushed, in the same commits as the report when there is one.
With lanes, every lane's foreman commits these records to the base. When the
push is rejected, fetch, reset the clone's base to `origin/<base>`, bring the
report files back from the session branch (`git checkout <session> --
docs/relatorios/<report>*`), redo the merge (append only rows that are absent),
commit and push again; never resolve
a conflict in these tables by hand. Copy the merged log back over the clone's
log and over the main checkout's (`<clone>/../../..`), so the scoreboard there
sees every lane.

Before this summary, check the feature acceptance scenarios in the original
`spec.md` against the integrated session. Run the small supported observable
probes, reusing existing evidence for identical code. Record scenario, outcome,
evidence and any unexamined coverage. Human playtests or unavailable devices
remain pending. Add `Acceptance` and `Disclosure` lines as ticket-flow defines. Refresh the existing session PR body by incorporating the new disclosures in
the existing ticket-linked acceptance/decision sections, with `gh api -X PATCH
repos/{owner}/{repo}/pulls/<n> -F body=@<file>` (`gh pr edit` fails on the
Linux runner); preserve the completed ticket count and approval lines. Metadata
updates are the exception to section 4's code-edit boundary: switch to the
session branch, commit only Acceptance/Disclosure and supporting evidence, push
that branch, then return to the base. The summary and PR carry the same pending acceptance. This is a feature
check from product goals, not another entire ticket review or full gate run.

Record the run's interventions once in `<tracker>/interventions.md`:
`| When | Ticket | Kind | Evidence |`, with an ISO timestamp, ticket id or `-`,
and a link to the note/commit. Kind is `human-rescue` (unplanned human work to
unblock execution), `routine-approval` (the intended merge/release decision),
`proxy-decision`, or `automatic-recovery`. A `proxy-decision` Evidence starts
with the line's head, `Proxy decided (<who>)`, so the scoreboard can separate
them.

Then one message in chat, then notify. The human reads it to act, so it holds
what they do next and what changed, and the run's mechanics live in the
records (report appendix, `interventions.md`, run log). Three blocks, in order:

- **Your turn** — first, and split in two:
  - *Needs you:* one line per action only the human can take: a `Needs your
    call` ticket (quote its question), a `Review: human` ticket, the session PR
    to merge, a stage stuck that you did not touch. With more than one lane, the
    merge order: from the main checkout, after `git fetch`, `git merge-tree
    --write-tree origin/<base> origin/<session>` per open lane PR; clean ones
    first, a conflicting one names its files. After the first merge the others
    sync (section 9).
  - *Nothing for you:* the `Approve` tickets as one line with their count and ids.
  - *Hand tests* only when the lane's feature is finished (every ticket of the
    lane `done`): the acceptance scenarios left pending for a person, as a
    checklist with where to look. Before that, one line: nothing to test by
    hand yet. Partial progress is not playtested.
- **What changed** — link the session PR, then one plain-language line per
  ticket (`report.md`, **What was done**): what changes for whoever uses the
  product, and where the risk is when there is one.
- **Record** — one line: the run's cost (the `Cost` column summed over this
  run's rows, per model, `?` rows counted apart; API list price, not what the
  plan charged; beside each Codex model, its share of the weekly Codex quota,
  `report.md`, **Codex quota**), and the report's PDF link with its two commits
  (section 7, **Record**) when there is one. Restarts, cleanups, proxy decisions
  and what you noticed and left alone go to the report's appendix, not the chat.

Meaningful production behavior authored during review needs the independent
review record required by ticket-flow; absence is a pending integration condition.

## 6. Finding attribution

A reopen rate says a ticket came back, not whose fault it was. Every `reopened`
review row of this run gets each of its findings labelled, so the scoreboard can
charge the implementer only for what was the implementer's.

A review that merges can hide the same miss: it writes the missing test or meets
the criterion itself instead of reopening. Every finding a merging
review fixed in a commit of its own, and that adds proof or behaviour (a test, a
criterion met, a red run the record lacked; not a comment or a rename), gets a
row too, with `Round` `0`. The scoreboard counts those apart, as fixed in review.

**Evidence per round:** the review's entry in `## Comments` that sent the ticket
back, the ticket as it stood when stage 2 ran, and the diff that stage reviewed.
Rebased branches lie: after a rebase, `git show <rev>^:<ticket>` can show text the
proxy added later. Rebuild the ticket from the session branch's commits.

**Rubric, one label per finding, first yes wins:**

1. Is the finding real — a defect or a missing proof a careful maintainer would
   accept? No → `S3-ruído`.
2. Is it in the ticket — a criterion, the Contract, the tests list, a decision in
   `## Comments`? Yes → `S2-explícito/código` (the code misses it) or
   `S2-explícito/teste` (no test fails when the fix is reverted).
3. Can the ticket plus the codebase get there — failure, cleanup and concurrency
   paths of the code stage 2 wrote, regressions of its own change, a convention the
   repo already follows? Yes → `S2-implícito`. No → `S1`.

Tie between S1 and S2: the fix needs a decision → `S1`; it needs only care → S2.
Append ` ?` to a borderline label. Two things belong to stage 3 whatever the label,
and get explicit flags plus evidence in the report: drip-feeding (a finding
visible in an earlier round, raised only now) and review-induced churn (a
regression born from the previous round's own advice).

**Never judge yourself.** When the round's reviewer is the model you run as (an
unversioned row such as `opus` counts as you if you are any Opus), the round goes to
GPT-6 Astra at medium effort, read-only, with this rubric and the evidence paths:

    codex exec -C <repo> -m gpt-6-astra -c model_reasoning_effort=medium -c approval_policy='"never"' --sandbox read-only --color never --output-last-message <scratch>/<id>-r<n>.md "<rubric + evidence>" < /dev/null

`< /dev/null` is required: `codex exec` waits on open stdin.

Its labels go in as returned. You may add a line of disagreement in the report,
never change the row.

**Record:** append to `<tracker>/reopen-attribution.md` (create it with the header
when missing), one row per finding, and commit it on the session branch with the
run's other tracker changes:

    | When | ID | Round | Implementer | Reviewer | Label | Finding | Why | Discovery | Origin | Review miss | Review churn |
    |---|---|---|---|---|---|---|---|---|---|---|---|

Use `Discovery: ticket-review` for the existing reopen/fixed-in-review records.
`Round` is the ticket's Nth reopened review row from the log's beginning, not
this run's; `0` is the merging review's fixes. Spell models as the run log does.
`Origin` links the responsible ticket and reviewed commit when known; otherwise
`unknown`. `Review miss` and `Review churn` are each `yes`, `no`, or `unknown`,
with evidence in `Why`. Preserve the S1/S2/S3 attribution: a review miss can also
be an implementation defect. No `|` inside a cell.

Before the summary, check new session PR reviews, release audit reports and
confirmed user defect reports since the last pass. Record confirmed defects
found **after ticket approval** in this table, linking the source in `Why`.
Discovery is `session-review`, `release-audit`, or `post-release`; `Round: -`.
Originating ticket/commit only when the history supports it, otherwise `ID: -`,
`Origin: unknown`, unknown models, `Label: unclassified`. These rows do not enter
the implementer/reviewer reopening rate. Link follow-up fixes to the same finding.
When a legacy eight-column table exists, append a twelve-column header before new
rows. Record each finding once, by its source report and finding location;
check those links before appending.

## 7. Report (runs of three or more tickets)

A run whose rows in `run-log.md` (the ones since launch, relaunches included)
name three or more distinct ids owes a PDF report. The chat summary scrolls
away; the report is what the human reads before the next run and compares
across runs. Fewer than three: the summary is enough.

- **Where:** `docs/relatorios/<yyyy-mm-dd>-sweatshop-<lineup>[-<lane>][-N].tex`
  and its `.pdf`. `-N` when that day already has one.
- **Record:** a report that is only written is not done; it is done when it is
  committed. Commit the `.tex` and the `.pdf` on the session branch and push, so
  they land in the session PR. Then commit the same two files, same path, on the
  base branch and push it too: the human reads from the base, and a report that
  lives only on the session branch is invisible until the merge. Only these
  records (report, run-log copy, `reopen-attribution.md`, `interventions.md`, and
  section 8's roadmap files) go to the base directly; code still goes
  through the session PR. Identical files on both sides merge clean. Leave the
  repo on the base branch.
  The summary names both commits next to the PDF link; no hashes there means the
  report was not recorded.
- **Build and content:** read [`report.md`](report.md) beside this file (build,
  shape, **What was done**, roadmap image, **Codex quota**, attribution,
  scoreboard rules) and follow it.

## 8. Published roadmap

A `Roadmap:` binding in `AGENTS.md` lists each roadmap with its command and when
it is published; publish as the binding says.

- **Per-session roadmap**: publish it at the end of every run, after the section 9
  sync, from the session branch. That branch is the base plus this lane, so the
  page shows the run's work before the merge. Its files stay out of git, as the binding says.
- **Every other roadmap**: publish from the main checkout, never from a lane,
  at the moment the binding names, or when the human asks. Only the base after
  the merge holds every lane's tickets, and two foremen would overwrite each
  other's pages. `git pull --ff-only` on the base, run the command, publish,
  then commit the regenerated tracked files on the base and push, as a record.
  When the binding's moment falls after this run's merge, the summary's
  **Your turn** ends with "merge the PR, then ask for the roadmap".

## 9. Sync with the base (lanes)

Another lane merged after this session opened leaves this lane's PR behind the
base, maybe in conflict, and its green check tested the session without the
other lane's code. Sync at the end of every lane run, as the last commit before
the chat summary (the run's records are on the base by then, so the base's side
of a record already holds this lane's rows), and again whenever the human says
another lane merged. Never while a driver runs on the clone. In the clone:

1. `git fetch`, switch to the session, `git pull --ff-only`. Done when
   `git merge-base --is-ancestor origin/<base> HEAD` succeeds.
2. `git merge --no-commit --no-ff origin/<base>`.
3. Resolve each conflict:
   - Section 5 and 7 records and section 8's roadmap files: take the base's side
     (`git checkout --theirs -- <file>`), never merge those tables by hand.
   - Code and tickets: keep both sides' intent. Read the ticket behind each side:
     this lane's on the session, the other's from `git log origin/<base> -- <file>`.
   - Sides that contradict (one removes or rewrites what the other relies on) are a
     contract call: ask the proxy as in section 4, with both tickets and the hunk.
     Escalated: `git merge --abort` and a **Your turn** line with the question.
4. Run the repo's sync gate on the uncommitted merge: the bindings' `Sync gate:`
   line, else `Gate:`. A `Sync gate:` covers tests the ticket gate skips, so at
   the end of a lane run it runs even when the merge brought nothing (step 2
   says "Already up to date"): run it on the session head, with the same
   handling. With only `Gate:` (no `Sync gate:`), skip it when the merge
   brought nothing or touches only files no test reads (prose docs `docs/`,
   `*.md`, and the tracker `.scratch/`; a test that loads one of them means
   gate it), as in `pr-review-loop`: the PR gate runs before approval. Note
   `sync gate skipped: <reason>` in step 5's comment; with nothing merged
   there is nothing to commit. Red: `git merge --abort` and a
   **Your turn** line with the failing test and both tickets; a fix is new code,
   which goes in a ticket, never in the sync. Green: commit
   `Merge <base> into <session>` and push the session branch.
5. `gh pr comment` on the session PR: the base commit merged, each file resolved
   by hand with one line on how, any proxy decision. The human reviews those
   hunks before merging. One line in the notes file; leave the clone on the base.

With lanes, the summary's **Your turn** ends with "after merging this PR, tell
the other open lanes' foremen to sync".

