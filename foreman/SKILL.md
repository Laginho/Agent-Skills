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
chat line and push notification with the lane's name. Which lane can start
next is `scout`'s question, not yours.

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

Otherwise launch the runtime's driver (the script selected by `sweatshop`). In
Claude Code, launch it as a **detached process** with its output in a file:

    Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','<script>','<repo>',<flags> -RedirectStandardOutput <tracker>/run-log/driver-<when>.out -RedirectStandardError <tracker>/run-log/driver-<when>.out.err -WindowStyle Hidden -PassThru

On Linux, from Bash (there `Start-Process` pipes the output through the launching
shell, so it stops when that shell exits); its pid is `pgrep -f '<script> <repo>'`:

    setsid pwsh -NoProfile -File <script> <repo> <flags> > <tracker>/run-log/driver-<when>.out 2> <tracker>/run-log/driver-<when>.out.err < /dev/null &

Not a background Bash/PowerShell task: those die at their `timeout`, 2 h at
most. The detached driver does not show in the session's task pane;
tell the human its pid and `.out` path. In Codex, a terminal session. A lineup the human asks for goes on the command line
(`-Lineup` or `-Models`, as `sweatshop/SKILL.md` says), never into the binding;
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

Never hold `<tracker>/run-log.md` open. On Windows a `tail -F` on it locks out
the driver's `Add-Content`, and the driver crashes on its next row. `TaskStop`
leaves the `tail` orphaned, so the lock outlives the monitor. To watch, poll the driver's `.out` every
30 s instead, from a background loop that exits on a new line (re-arm it each
wake; it too dies at 2 h): it prints one line per finished stage
(`<id> <stage> (<model>): <outcome>, $<cost>`) and every `throw`.

## 2. Per stage, and the heartbeat

**Each finished stage** is a QA read, not a count. When the driver prints its
line, open that stage's `.final` (the session's last message) and check it
against the outcome: a `to-review` whose last message admits a skipped test, a
merge whose review raised something it then waved through, a `blocked` question
the proxy can answer (section 4). One line in chat and in the notes file: what
the stage did and anything that looks wrong. An outcome says the stage ended,
not that it was right, and the driver has already moved on to the next ticket.

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
blocked. The existing hard-model escalation remains; changing the model alone
is not the diagnosis. This diagnosis takes precedence over the generic blocked
question handling below.

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

**Live panel**, when `AGENTS.md` has a `Painel` binding (a claude.ai artifact
URL): the page the human follows the run on, one card per lane. Write it with
`ArtifactData`, document `lanes/<lane>`, a whole-document `set` pinned with
`if_version` to the version you last read:

    { "session": "<session branch>", "driver": "running|finished|stopped|crashed",
      "current": null | { "id": "", "title": "", "stage": "specify|implement|review",
                          "model": "", "startedAt": "<ISO, with offset>", "limitMin": 45 },
      "tickets": [ { "id": "", "title": "", "state": "done|running|ready|waiting|blocked|human", "note": "" } ],
      "events": [ { "at": "<ISO>", "text": "" } ],
      "pr": "<github url> or null", "needsHuman": "<what waits on the human> or null",
      "updatedAt": "<ISO>" }

Write it at launch or adoption, at every finished stage, at every check-in and at
the end (`driver` finished or crashed, `current` null, `pr` set). A finished
stage's write also sets `current` to the stage the driver started right after
it (its newest stage `.txt`), so the card never reads "between stages" while
one runs; this costs no extra wake. Keep the last 8 events, one short line each.
At launch, delete the documents of lanes whose `driver` is not `running`: a past
run's lane would read as this run's. A pinned write that fails: re-read and
redo. Failing twice: a line in the notes and go on; the panel never stops a run.

## 3. Crash

The driver's process is gone and its `.out` ends in a `throw` message, or a
check-in finds a `.err` file with content and no live `.txt`. Read the tail of
the stage's `.txt`, `.final` and `.err`, the driver's `.out` and `.out.err`, and `git -C <repo> status`.
Say what happened, then push-notify.

The driver owns each stage's process job; completed runtimes get a short exit
grace, and cleanup stops only that job. Read `<stage>.runtime.json` for completion,
exit, forced cleanup and infrastructure errors. Leave shared processes alone;
process names are not ownership evidence.

Before resetting interrupted work, inspect `run-log/recovery.txt`: the driver
saves recovery refs under `refs/sweatshop-recovery/` and stashes dirty work,
including untracked files. Preserve those refs and stashes until recovery is
verified. A driver killed before saving needs the same preservation **before**
checkout/reset: save HEAD under a new recovery ref, stash tracked and untracked
edits if present, retain the stash ref, and record both. Ignored runtime evidence
stays in `run-log/`; preserve any needed ignored project output separately.

- `implementing`: preserve the ticket branch under `recovery/<timestamp>/<id>`
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
A usage limit is not a crash: the driver sleeps until the reset the CLI names
(`usage limit; waiting until HH:mm`). Only a limit without a time (a dated or
weekly reset) still stops it.

## 4. Hands off

The human's calls stay the human's: questions the proxy escalated, the session
PR merge, any edit to code on the session branch other than section 9's sync. An edit you would have made is
a line in the summary, not a commit. No subagents: the proxy is
`sweatshop/scripts/proxy.ps1` (`ticket-flow`, "Asking the proxy").

**Push only the session branch and the base.** Never push a ticket branch, even
after committing a diagnosis on it: review rebases ticket branches locally, and a
stale `origin` copy makes the branch ambiguous to every reader. A hook in `~/.claude/settings.json` refuses it too.

**A `blocked` ticket with no `Proxy escalated` line is not the human's yet.**
The driver already puts a stage's question to the proxy during the run; what is
left came from a third ask in one run, a proxy call that failed, or an older run.
Run `sweatshop/scripts/proxy.ps1` with the ticket id and a question built from
`## Comments` and the stage's `.txt`, plus the branch the driver kept for the
attempt (`recovery/asked/<when>/<ID>`, or a legacy `<branch>-asked-<when>`, named
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
both pushed, in the same commits as the report when there is one. Never
un-exclude the original.

With lanes, every lane's foreman commits these records to the base. When the
push is rejected, fetch, reset the clone's base to `origin/<base>`, bring the
report files back from the session branch (`git checkout <session> --
docs/relatorios/<report>*`), redo the merge (append only rows that are absent),
commit and push again; never resolve
a conflict in these tables by hand. Copy the merged log back over the clone's
log and over the main checkout's (`<clone>/../../..`), so the scoreboard there
sees every lane.

One message in
chat, then notify. Three blocks:

Before this summary, check the feature acceptance scenarios in the original
`spec.md` against the integrated session. Run the small supported observable
probes, reusing existing evidence for identical code. Record scenario, outcome,
evidence and any unexamined coverage. Human playtests or unavailable devices
remain pending. Add `Acceptance` and `Disclosure` lines as ticket-flow defines,
including known deferred defects, links and integration/release impact. Updating
an older done ticket's comments provides context, not a newly produced ticket.
Refresh the existing session PR body by incorporating the new disclosures in
the existing ticket-linked acceptance/decision sections, with `gh pr edit
--body-file`; preserve the completed ticket count and approval lines. Metadata
updates are the exception to section 4's code-edit boundary: switch to the
session branch, commit only Acceptance/Disclosure and supporting evidence, push
that branch, then return to the base. The summary and PR carry the same pending acceptance. This is a feature
check from product goals, not another entire ticket review or full gate run.

- **Produced** — the session PR's body, in its order: `Needs your call` and
  `Review: human` first, `Approve` lines after. Link the PR. Each ticket named
  there gets one plain-language line, as in the report (section 7, **What was
  done**). End with the run's
  cost: the `Cost` column summed over this run's rows, per model, with `?` rows
  counted apart. It is API list price, not what the plan charged. Beside each
  Codex model's cost, the share of the weekly Codex quota it spent (section 7,
  **Codex quota**).
  Link the report's PDF when there is one, with its two commits (section 7,
  **Record**).
- **Foreman** — restarts, cleanups, every `Proxy decided` line grouped by who
  decided (the model in its parentheses; older lines say `opus` or
  `gpt-6-astra high, fallback`, and a line without `(<who>)` is legacy, unknown),
  anything you noticed and left alone. Count the ones the driver answered for a
  runtime that could not reach the proxy (its `proxy from <runtime> sessions` line
  in the `.out`). An older proxy line with no receipt, written by the stage's own
  model, is not a proxy decision: list it apart, as the stage's judgement. Record interventions once in `<tracker>/interventions.md`:
  `| When | Ticket | Kind | Evidence |`, with an ISO timestamp, ticket id or `-`,
  and a link to the note/commit. Kind is `human-rescue` (unplanned human work to
  unblock execution), `routine-approval` (the intended merge/release decision),
  `proxy-decision`, or `automatic-recovery`. A `proxy-decision` Evidence starts
  with the line's head, `Proxy decided (<who>)`, so the scoreboard can separate
  them. A routine approval is not a rescue.
  Commit this record with the attribution. Older missing records are unknown.
- **Your turn** — one line per action only the human can take: this ticket
  needs your decision (quote the question from `## Comments`), this PR needs your
  review, this stage is stuck and I did not touch it.

Every confirmed unresolved finding found here needs an open follow-up or an
explicit accepted deferral with impact and evidence. Closed-ticket Comments
alone are history; preserve their link and give the finding a visible destination.
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

Close its stdin as above: with stdin open, `codex exec` prints "Reading additional
input from stdin..." and waits forever.

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
confirmed user defect reports available since the last attribution pass. Record
confirmed defects found **after ticket approval** in this same table, linking
the original report/finding in `Why`; do not start another audit. Discovery is
`session-review`, `release-audit`, or `post-release`; use `Round: -`. Identify the
originating ticket/commit only when the history supports it, otherwise `ID: -`,
`Origin: unknown`, and unknown models. Use `Label: unclassified` until evidence
supports the existing rubric. These rows count discoveries separately; they do
not enter the implementer/reviewer reopening rate. A pre-release audit catch is
not a post-release defect. Link follow-up fixes to the same finding instead of
counting each repeat audit as a new defect. Do not infer absence of defects from
absence of reports, or count unconfirmed suspicions as defects.

Keep historical eight-column tables intact; append a twelve-column header before
new rows. Older flags remain unknown. Record each finding once using its source
report and finding location; subsequent runs check those links before appending.
The audit remains read-only except its report: attribution is done here, after
that report exists. Commit attribution and interventions on the session with the
run records. A confirmed later report can be incorporated at the next foreman
summary; publication does not depend on completing this bookkeeping.

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
- **Build:** any LaTeX engine on the PATH (`tectonic -X compile <file>.tex`).
  The preamble loads `fontspec`, not `inputenc`/`fontenc`: Tectonic is XeTeX, and the T1
  font drops — and … (measured 2026-10-31).
  Recompile until there are no overfull-box warnings. None: Codex's bundled
  Tectonic under `~/.codex/.tmp/`, which a `codex update` can delete. Still none: commit the `.tex`, say so in the summary, and offer to
  download Tectonic from its GitHub release into a folder on the PATH.
- **Shape:** the newest report in `docs/relatorios/` is the template; keep its
  sections so runs compare side by side. Without one: summary (produced, cost,
  the one thing that went wrong, provisional verdict), timeline, per-stage table
  (minutes, tokens, cache, output, cost, outcome) with a chart of where the input
  went and what was wasted, comparison with the previous runs from `run-log.md`,
  observations per model, driver and runtime issues, numbered recommendations,
  every `Débito humano:` line of the run, and every `Proxy decided` line of the
  run's tickets, quoted per ticket with who decided (the model in the line,
  or legacy unknown). Those are the calls made on the human's
  behalf; a count without the text sends them hunting through the tickets.
- **What was done:** right after the summary, one short paragraph per ticket the
  run worked on, for a reader who never opened the tickets (a ticket's title and
  criteria are too abstract and too specific). Say what changes for whoever uses
  the product, the main file, and for each reopen what was broken, its cause and
  the file, as in "BUG-001: the scroll broke below 854x480; a hard-coded
  `set_size` in `render_ui.py` caused it." Sources: the ticket on the session
  branch, its merge diff and the review findings (section 6), never memory.
  Tickets of one kind (content drafts) can share a paragraph with a line each.
- **Roadmap image:** when `AGENTS.md` has a `Roadmap:` binding, the per-session
  roadmap as this run left it goes right after **What was done**. On the
  session branch, run the binding's per-session command, render its SVG to
  `docs/relatorios/<report>-roadmap.png` as the binding says, and
  `\includegraphics` it. Then restore the files the command wrote
  (`git checkout -- <files>`) before committing anything: they are tracked, and
  every lane would conflict on them. Commit the PNG with the `.tex` and `.pdf`.
  A generator that fails means no image: quote its error in the report and go on.
- **Codex quota:** next to the cost per model, the percentage of the weekly
  Codex quota each Codex model spent, from `sweatshop/scripts/codex-quota.ps1
  -Tracker <tracker> -Since <launch> -Until <last row>`. Split a model that
  played two roles (hard implementer and reviewer) by stage. Name the plan, say
  the total is exact while one stage is ±1 point (Codex rounds to integers), name
  any Codex thread that ran outside the stages (it shares the quota), and say so
  when the weekly window reset mid-run. Claude models get `--`.
- **Reopen attribution:** section 6's rows for this run as a table (ticket, round,
  finding, label, why, and who judged it when it was not you), the totals per label,
  and the review-miss and churn cases. Separate session-review, release-audit and
  post-release discoveries, retaining unknown origins. Place it before the scoreboard, since the
  scoreboard reads them.
- **Scoreboard:** a section with the output of `sweatshop/scripts/scoreboard.ps1`,
  run over every repo on this machine that has a `<tracker>/run-log.md` (this run's
  repo and its siblings), pasted as printed. Never a lane's clone: after the
  copy-back it holds the whole history, and every row would count twice. It is cumulative, not this run's alone:
  it is how the human picks lineups from real tickets instead of a dedicated
  benchmark. Compare it with the previous report's scoreboard and name the rows that
  moved. Read it under three rules:
  - A reopen rate belongs to the implementer → reviewer pair. Compare implementers
    only under the same reviewer, and reviewers only over the same implementer.
  - A pair under 10 reviews is an anecdote. Say so next to any conclusion drawn from it.
  - A row without an effort (`sonnet`, `gpt-6-luna`) predates the effort column.
    Never fold it into a row that has one.
  - Judge an implementer by the `S2 rate`, not the raw reopen rate: a reopen with no
    S2 finding was the spec's or the reviewer's. While `Unclassified` is above zero
    the S2 rate is a floor. `S1` counts in the findings table point at stage 1,
    `S3 noise` at the reviewer. Read `Fixed in review for S2` beside the S2 rate:
    a reviewer that fixes instead of reopening shows a low rate and a high fixed
    count, and the implementer's misses are the two added together.

  Read the evidence table as counts within recorded coverage, not defect rates.
  Compare human rescues separately from routine approvals, proxy decisions and
  automatic recoveries. `Shutdown s` is sampled runtime-completion to process-exit
  delay, including forced shutdown; `?` is unmeasured, never zero. Preserve missing
  history as unknown rather than comparing it with newly instrumented runs.

  A recommendation to change a lineup names the scoreboard rows it rests on.
- **Numbers come from the logs, never from memory:** `run-log.md` rows, the
  stages' `.txt` (Codex: `turn.completed` usage), `git log` of the session. A
  count you did not recompute from them does not go in. When a row's outcome
  lies (the driver read a stale copy), say so and report what really happened.

## 8. Published roadmap

A `Roadmap:` binding in `AGENTS.md` lists each roadmap with its command, its page
and when it is published. Publishing one means: render the PNG, read the page
first (the human edits it), replace its image, and fetch it again to confirm.
Without a tool for the pages, leave the PNG and say where it is.

- **Per-session roadmap**: publish it at the end of every run, after the section 9
  sync, from the session branch. That branch is the base plus this lane, so the
  page shows the run's work before the merge. It is the same image the report
  embeds (section 7). Its files stay out of git, as the binding says.
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
   handling. Red: `git merge --abort` and a
   **Your turn** line with the failing test and both tickets; a fix is new code,
   which goes in a ticket, never in the sync. Green: commit
   `Merge <base> into <session>` and push the session branch.
5. `gh pr comment` on the session PR: the base commit merged, each file resolved
   by hand with one line on how, any proxy decision. The human reviews those
   hunks before merging. One line in the notes file; leave the clone on the base.

With lanes, the summary's **Your turn** ends with "after merging this PR, tell
the other open lanes' foremen to sync".

