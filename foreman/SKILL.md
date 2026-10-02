---
name: foreman
description: Runs a sweatshop run with someone watching — launches the driver as a background task, reads each finished stage, sends a heartbeat every 30 minutes, cleans up after a crash, and hands the human a summary at the end. Use when asked to "run the foreman", "supervise the sweatshop", "babysit the loop", or with /foreman.
---

# Foreman

You supervise one `sweatshop` run from this session. The driver still owns the
loop and `ticket-flow` still owns every stage; you own the watching. Read
`sweatshop/SKILL.md` first: it says where the driver is, what it writes and what
"finished" looks like.

Language follows `standup`'s rule.

## 1. Standup, then launch

Run `/standup`. Stop here and say why when it shows any of: no unblocked
ticket, a dirty tree, a ticket at `implementing` or `reviewing`, or `blocked`
tickets waiting on the human and nothing else runnable. The driver's Preflight
would refuse the same things; you refuse them with the tree in view.

Otherwise launch the runtime's driver as a **background task** of this session
(Claude Code's Bash background mode or a Codex terminal session; use the script
selected by `sweatshop`). A lineup the human asks for goes on the command line
(`-Lineup` or `-Models`, as `sweatshop/SKILL.md` says), never into the binding;
none asked for, run the default. A pause the human asks for is the driver's
`STOP` file (`sweatshop/SKILL.md`), never a kill. Note the
launch time and the last row of `<tracker>/run-log.md`: everything after that row
is this run. In Claude Code, the check-in clock is a background Bash
`sleep 1800` that you re-arm on every wake: its completion notice always wakes
you. Not `/loop` or a cron job: measured 2026-09-24, one never fired and nobody
noticed for 30 minutes. In Codex, use a 30-minute thread heartbeat.

**Keep notes in a file**, `<tracker>/run-log/foreman-notes.md` (excluded with the
rest of `run-log/`): one timestamped line per launch, stage row, cleanup, proxy
call and human request, then a `## Pending` list of what the run still owes. A
run outlives the session watching it; measured 2026-09-30, a Claude Code restart
mid-run lost nothing because the notes held the launches, the pinned refs and
the owed report. After a restart, read them first and resume from `## Pending`.

Never hold `<tracker>/run-log.md` open. On Windows a `tail -F` on it locks out
the driver's `Add-Content`, and the driver crashes on its next row. `TaskStop`
leaves the `tail` orphaned, so the lock outlives the monitor; measured
2026-09-24, it crashed the driver twice. To watch, poll the driver's own task
output every 30 s instead: it prints one line per finished stage
(`<id> <stage> (<model>): <outcome>, $<cost>`) and every `throw`.

## 2. Per stage, and the heartbeat

**Each finished stage** is a QA read, not a count. When the driver prints its
line, open that stage's `.final` (the session's last message) and check it
against the outcome: a `to-review` whose last message admits a skipped test, a
merge whose review raised something it then waved through, a `blocked` question
the proxy can answer (section 4). One line in chat and in the notes file: what
the stage did and anything that looks wrong. An outcome says the stage ended,
not that it was right, and the driver has already moved on to the next ticket.

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

The background task ended and its output ends in a `throw` message, or a
check-in finds a `.err` file with content and no live `.txt`. Read the tail of
the stage's `.txt`, `.final` and `.err`, the task's own output, and `git -C <repo> status`.
Say what happened, then push-notify.

The driver's `finally` already restores the tree and returns to the base, so a
stuck ticket, not a dirty tree, is what a crash leaves. A driver killed from
outside (the session's tasks stopped, the machine off) skips `finally`: copy the
uncommitted diff into `<tracker>/run-log/`, restore the tree and check out the
base yourself, then:

- `implementing`: delete the ticket's branch (`<id>` lowercased). The ticket reads
  `to-implement` again from the session; a half-written stage is worthless
  without the session that wrote it, and `ticket-flow` says never continue
  blind.
- `reviewing`: flip `Stage:` back to `to-review` on the ticket's branch, where
  the driver reads it, and on the session branch when the driver parked it there
  as `blocked` (`Review ended at reviewing (timeout)`); commit both.

**Restart once**, as a background task again, when the cause is environmental:
API outage, network, `gh` or `git` transport, machine went to sleep. Any other
cause — a `throw` from Preflight, a script bug, the same stage failing twice —
you report and stop; a logic failure restarted is the same failure paid twice.
A usage limit is not a crash: the driver sleeps until the reset the CLI names
(`usage limit; waiting until HH:mm`). Only a limit without a time (a dated or
weekly reset) still stops it.

## 4. Hands off

The human's calls stay the human's: questions the proxy escalated, the session
PR merge, any edit to code on the session branch. An edit you would have made is
a line in the summary, not a commit. Subagents: only the proxy.

**A `blocked` ticket with no `Proxy escalated` line is not the human's yet.**
It came from a runtime or a session that did not ask the proxy. Spawn the repo's
`proxy` agent with the ticket id, the question and the evidence from `## Comments`
and the stage's `.txt`, plus the branch the driver kept for the attempt
(`<branch>-asked-<when>`, named in the `Attempt N stopped to ask` line), so the
answer can say "resume from it" instead of starting over. Follow
`ticket-flow`'s "Asking the proxy": record
`Proxy decided` (folded into the body when it changes the contract) and set
`to-implement`, or record `Proxy escalated`. Commit on the session branch, then
relaunch the driver once the run is over. A relaunch for proxy answers is not
the one restart of section 3.

## 5. Summary (when the task ends)

Stop the check-ins. When the run reopened a ticket, attribute it first
(section 6); when it owes a report (section 7), write and commit that next.

Every run, report or not, commits the run log. The driver keeps
`<tracker>/run-log.md` out of git on purpose (it resets the tree between
stages), so that file lives on one disk only, and it is what the scoreboard
compares models from. Merge it into `docs/run-log/run-log.md`, never copy over
it: the copy can hold rows another machine logged (measured 2026-10-02, a copy
over it would have deleted 38). Append this run's rows to the copy, then copy
the merged file back over the local log, so both disks start the next run with
the whole history. Commit the copy on the session branch and on the base branch,
both pushed, in the same commits as the report when there is one. Never
un-exclude the original.

One message in
chat, then notify. Three blocks:

- **Produced** — the session PR's body, in its order: `Needs your call` and
  `Review: human` first, `Approve` lines after. Link the PR. End with the run's
  cost: the `Cost` column summed over this run's rows, per model, with `?` rows
  counted apart. It is API list price, not what the plan charged.
  Link the report's PDF when there is one, with its two commits (section 7,
  **Record**).
- **Foreman** — restarts, cleanups, every `Proxy decided` line, anything you
  noticed and left alone.
- **Your turn** — one line per action only the human can take: this ticket
  needs your decision (quote the question from `## Comments`), this PR needs your
  review, this stage is stuck and I did not touch it.

## 6. Reopen attribution (every run with a reopen or a review fix)

A reopen rate says a ticket came back, not whose fault it was. Every `reopened`
review row of this run gets each of its findings labelled, so the scoreboard can
charge the implementer only for what was the implementer's.

A review that merges can hide the same miss: it writes the missing test or meets
the criterion itself instead of reopening (measured 2026-10-02, Opus 5.5 xhigh did
this on 4 of 5 merges and the scoreboard read 0 %). Every finding a merging
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
and go in the report's prose: drip-feeding (a finding visible in an earlier round,
raised only now) and review-induced churn (a regression born from the previous
round's own advice).

**Never judge yourself.** When the round's reviewer is the model you run as (an
unversioned row such as `opus` counts as you if you are any Opus), the round goes to
GPT-6 Astra at medium effort, read-only, with this rubric and the evidence paths:

    codex exec -C <repo> -m gpt-6-astra -c model_reasoning_effort=medium -c approval_policy='"never"' --sandbox read-only --color never --output-last-message <scratch>/<id>-r<n>.md "<rubric + evidence>" < /dev/null

Close its stdin as above: with stdin open, `codex exec` prints "Reading additional
input from stdin..." and waits forever (measured 2026-10-02, 10 min lost).

Its labels go in as returned. You may add a line of disagreement in the report,
never change the row.

**Record:** append to `<tracker>/reopen-attribution.md` (create it with the header
when missing), one row per finding, and commit it on the session branch with the
run's other tracker changes:

    | When | ID | Round | Implementer | Reviewer | Label | Finding | Why |
    |---|---|---|---|---|---|---|---|
    | 2026-09-27 | CLEAN-012 | 1 | sonnet | opus | S2-implícito | Filter bypassed by a `userId@` authority | Care, not a decision: the ticket is a trust boundary (d9e5300) |

`Round` is the ticket's Nth `reopened` review row in `run-log.md`, counting from
the log's first row, not this run's: it is how `scoreboard.ps1` joins the two.
`0` is the merging review's own fixes.
`Implementer` and `Reviewer` are spelled as that log's `Model` column spells them.
`When` is the reopen's date. No `|` inside a cell. Rows already in the file stay:
the file is history, like the log.

## 7. Report (runs of three or more tickets)

A run whose rows in `run-log.md` (the ones since launch, relaunches included)
name three or more distinct ids owes a PDF report. The chat summary scrolls
away; the report is what the human reads before the next run and compares
across runs. Fewer than three: the summary is enough.

- **Where:** `docs/relatorios/<yyyy-mm-dd>-sweatshop-<lineup>[-N].tex` and its
  `.pdf`. `-N` when that day already has one.
- **Record:** a report that is only written is not done; it is done when it is
  committed. Commit the `.tex` and the `.pdf` on the session branch and push, so
  they land in the session PR. Then commit the same two files, same path, on the
  base branch and push it too: the human reads from the base, and a report that
  lives only on the session branch is invisible until the merge. Only these
  records (report, run-log copy, `reopen-attribution.md`) go to the base directly; code still goes
  through the session PR. Identical files on both sides merge clean. Leave the
  repo on the base branch.
  The summary names both commits next to the PDF link; no hashes there means the
  report was not recorded.
- **Build:** any LaTeX engine on the PATH (`tectonic -X compile <file>.tex`).
  Recompile until there are no overfull-box warnings. None: Codex's bundled
  Tectonic under `~/.codex/.tmp/`, which a `codex update` can delete (measured
  2026-10-01). Still none: commit the `.tex`, say so in the summary, and offer to
  download Tectonic from its GitHub release into a folder on the PATH.
- **Shape:** the newest report in `docs/relatorios/` is the template; keep its
  sections so runs compare side by side. Without one: summary (produced, cost,
  the one thing that went wrong, provisional verdict), timeline, per-stage table
  (minutes, tokens, cache, output, cost, outcome) with a chart of where the input
  went and what was wasted, comparison with the previous runs from `run-log.md`,
  observations per model, driver and runtime issues, numbered recommendations,
  every `Débito humano:` line of the run, and every `Proxy decided` line of the
  run's tickets, quoted per ticket. Those are the calls made on the human's
  behalf; a count without the text sends them hunting through the tickets.
- **Reopen attribution:** section 6's rows for this run as a table (ticket, round,
  finding, label, why, and who judged it when it was not you), the totals per label,
  and the drip-feeding and churn cases. Place it before the scoreboard, since the
  scoreboard reads them.
- **Scoreboard:** a section with the output of `sweatshop/scripts/scoreboard.ps1`,
  run over every repo on this machine that has a `<tracker>/run-log.md` (this run's
  repo and its siblings), pasted as printed. It is cumulative, not this run's alone:
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

  A recommendation to change a lineup names the scoreboard rows it rests on.
- **Numbers come from the logs, never from memory:** `run-log.md` rows, the
  stages' `.txt` (Codex: `turn.completed` usage), `git log` of the session. A
  count you did not recompute from them does not go in. When a row's outcome
  lies (the driver read a stale copy), say so and report what really happened.

