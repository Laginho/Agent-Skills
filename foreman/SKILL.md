---
name: foreman
description: Runs a sweatshop run with someone watching — launches the driver as a background task, checks in every 30 minutes, cleans up after a crash, and hands the human a summary at the end. Use when asked to "run the foreman", "supervise the sweatshop", "babysit the loop", or with /foreman.
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
selected by `sweatshop`). Note the
launch time and the last row of `<tracker>/run-log.md`: everything after that row
is this run. In Claude Code, the check-in clock is a background Bash
`sleep 1800` that you re-arm on every wake: its completion notice always wakes
you. Not `/loop` or a cron job: measured 2026-09-24, one never fired and nobody
noticed for 30 minutes. In Codex, use a 30-minute thread heartbeat.

Never hold `<tracker>/run-log.md` open. On Windows a `tail -F` on it locks out
the driver's `Add-Content`, and the driver crashes on its next row. `TaskStop`
leaves the `tail` orphaned, so the lock outlives the monitor; measured
2026-09-24, it crashed the driver twice. To watch for trouble, poll the
driver's own task output every 30 s instead.

## 2. Check-in (every 30 minutes)

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
the stage's `.txt` and `.err`, the task's own output, and `git -C <repo> status`.
Say what happened, then push-notify.

The driver's `finally` already restores the tree and returns to the base, so a
stuck ticket, not a dirty tree, is what a crash leaves:

- `implementing`: delete the ticket's branch (`<id>` lowercased). The ticket reads
  `to-implement` again from the session; a half-written stage is worthless
  without the session that wrote it, and `ticket-flow` says never continue
  blind.
- `reviewing`: flip `Stage:` back to `to-review` on the session branch, commit.

**Restart once**, as a background task again, when the cause is environmental:
API outage, network, `gh` or `git` transport, machine went to sleep. Any other
cause — a `throw` from Preflight, a script bug, the same stage failing twice —
you report and stop; a logic failure restarted is the same failure paid twice.

## 4. Hands off

The human's calls stay the human's: questions the proxy escalated, the session
PR merge, any edit to code on the session branch. An edit you would have made is
a line in the summary, not a commit. Subagents: only the proxy.

**A `blocked` ticket with no `Proxy escalated` line is not the human's yet.**
It came from a runtime or a session that did not ask the proxy. Spawn the repo's
`proxy` agent with the ticket id, the question and the evidence from `## Comments`
and the stage's `.txt`, and follow `ticket-flow`'s "Asking the proxy": record
`Proxy decided` (folded into the body when it changes the contract) and set
`to-implement`, or record `Proxy escalated`. Commit on the session branch, then
relaunch the driver once the run is over. A relaunch for proxy answers is not
the one restart of section 3.

## 5. Summary (when the task ends)

Stop the check-ins. One message in chat, then notify. Three blocks:

- **Produced** — the session PR's body, in its order: `Needs your call` and
  `Review: human` first, `Approve` lines after. Link the PR.
- **Foreman** — restarts, cleanups, every `Proxy decided` line, anything you
  noticed and left alone.
- **Your turn** — one line per action only the human can take: this ticket
  needs your decision (quote the question from `## Comments`), this PR needs your
  review, this stage is stuck and I did not touch it.
