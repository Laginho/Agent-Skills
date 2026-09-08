---
name: "standup"
description: "Project-state brief at the start of a work session: what was done recently, what is open, what to pick up next. Use when the user asks for a standup, \"where were we\", \"what's the state of the project\", or invokes /standup. Reads the repo's local issue tracker (.scratch/) and git; not a daily/calendar brief."
---

# Standup

Answer the three standup questions for the current repo: what got done, what is in
progress or open, what comes next. Read-only. Output in chat, not a file.

## Where the facts come from

1. **Project instructions first.** `CLAUDE.md` / `AGENTS.md` name the tracker and its
   conventions. Follow those pointers; do not go hunting for TODO files.
2. **Tracker.** The standard layout is `.scratch/<feature>/` with `spec.md`, one ticket
   per file under `issues/`, and optionally `ledger.md`. Ticket filenames vary by repo
   (`NN-slug.md`, `KEY-N-slug.md`, …) — glob the directory rather than assuming a shape,
   and read `docs/agents/issue-tracker.md` for the repo's own convention when it exists.
   - Ticket status: match `\*{0,2}Status:\*{0,2}\s*(\S+)` in the first ~30 lines.
     Closed = `complete`, `resolved`, `wontfix`. Everything else is open
     (`open`, `claimed`, `blocked`, `ready-for-agent`, `ready-for-human`, `needs-*`).
   - `Priority:` and `Blocked by:` lines, when present, order the "next" list.
   - `ledger.md` is a recent-activity log. Column layout varies by repo and it may be
     a bare table (`date | ID | commit`) with no prose. Read the last rows for IDs and
     dates; cross-reference the IDs against `git log` to learn what each one was.
3. **Resolve blockers.** This is a required step, not optional color. Build a table of
   every ticket: `ID | status | priority | blocked-by IDs`, across all features in one
   pass. Then, for each open ticket, look up the status of every ID in its
   `Blocked by:` line. A blocker that is closed does not block. A ticket is
   **unblocked** when it has no `Blocked by:` line or all of its blockers are closed.
   Do this lookup literally; do not infer cycles or ordering from the IDs alone. Expect
   1–4 unblocked tickets in a healthy tracker; zero means a dependency error worth
   naming.
   - **Accepted debt is not work.** A feature dir whose name says debt (`debitos`,
     `debt`, `accepted`) or whose tickets carry no `Priority:` line holds deliberate
     deferrals. Count them on one line in **Aberto** as accepted debt; never list them
     in **Desbloqueado** and never recommend them.
4. **Git.** `git log --oneline -15` and `git log --oneline -10 -- .scratch/` to find
   which features moved most recently and what closed. `git status --short` for a
   dirty tree. Ignore whole-tree CRLF noise (`--ignore-cr-at-eol` gives zero diff).
5. **Active feature** = the `.scratch/` dir with the most recent commits, not
   directory mtime. Skip commits that touch more than one feature dir (tracker
   migrations, header sweeps): they are housekeeping, not feature work. If every
   recently touched feature is fully closed, the active feature is the first one in
   dependency order with open tickets.

Never read closed tickets' bodies for the brief; they are history, not state.

## Output

Portuguese if the repo's docs are in Portuguese, otherwise English. Five short blocks,
plain prose or one-line bullets, no headers wider than this:

**Feito** — the last 2–3 closed tickets or ledger entries, feature-level, with IDs and
dates. Tickets only: no commit hashes, and never lead with tracker migrations, header
sweeps or other housekeeping commits.

**Em andamento** — claimed/in-progress tickets, plus a dirty working tree if any.

**Aberto** — count of open tickets per feature, and the count must equal the number of
open ticket files you saw; name the top 3 by priority/dependency order. If a
phase/feature is fully closed, say so in one line and move on.

**Desbloqueado** — every unblocked ticket from step 3, one per line: `ID (priority) —
title`. This block is mandatory and is the reader's actual work queue. A ticket whose
only blockers are closed belongs here.

**Próximo passo** — one recommendation: the first open, unblocked ticket in dependency
order, with its path. If nothing is open: say the tracker is empty and offer three
concrete options (code audit, bug hunt against a named area, new feature from the
spec) — do not invent tickets.

Under 30 lines total. No preamble, no restating the layout.

## When the repo does not follow the layout

If there is no `.scratch/` and project instructions name no tracker: report the last
5 commits and the dirty tree, then say in one line that there is no issue tracker to
read and point at the `.scratch/<feature>/issues/` one-file-per-ticket convention. Do not guess
next steps from diffs.

