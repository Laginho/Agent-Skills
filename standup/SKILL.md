---
name: "standup"
description: "Project-state brief at the start of a work session: where the project stands and its next steps, in product terms rather than tickets. Use when the user asks for a standup, \"where were we\", \"what's the state of the project\", or invokes /standup. Reads the repo's local issue tracker (.scratch/) and git; not a daily/calendar brief."
---

# Standup

Say where the project stands and what comes next, in product terms: features, units
and milestones, not ticket IDs. The tracker and git are the evidence; the brief is the
output. Read-only apart from `git pull --ff-only`. Output in chat, not a file.

## Where the facts come from

1. **Project instructions first.** `CLAUDE.md` / `AGENTS.md` name the tracker and its
   conventions. Follow those pointers.
2. **Branches.** Do this before reading any ticket. Refresh first:
   `git fetch --all --prune`, then `git pull --ff-only` (step 5 says what to do when
   it fails). `<base>` is the bindings' base branch from `AGENTS.md`, else the
   default branch.
   - **Loop's base.** A `sweatshop/*` branch not merged into `<base>`, local or
     remote (`git branch -a --no-merged <base> --list '*sweatshop/*'`), is an open
     sweatshop session: tickets merge into it, not into `<base>`, and tickets
     created during the run exist only there. When one exists it is the loop's
     base; otherwise `<base>` is. Read the tracker from the loop's base —
     `git ls-tree -r --name-only <loop base> -- .scratch/` to list,
     `git show <loop base>:<path>` to read — never from the working tree unless it
     is the loop's base checked out. Note an open session with
     `git rev-list --count <base>..<session>` commits ahead. Lane sessions
     (`sweatshop/<lane>/<stamp>`) can be open side by side: each is the loop's base
     for the tickets in `.scratch/<lane>/`; read every other ticket from `<base>`.
   - **Ticket branches.** Resolve `sweatshop/scripts/ticket-state.ps1` from the
     installed skills and run `powershell -NoProfile -File <helper> -Repo <repo>
     -Id <ID> -IncludeRemote` for each ticket; report an ambiguity it raises.
     For each open ticket whose branch
     exists and is not merged into the loop's base, read it with
     `git show <branch>:<path>`. Exception: `blocked` on the loop's base wins — that
     is the driver parking the ticket. A ticket branch already merged is stale;
     name those in one line so they can be deleted.
     `done` on an unmerged ticket branch is invalid handoff, not a closed blocker:
     report the preserved branch and require merge/reopen repair before recommending
     its dependents.
   - **Everything else.** Any other branch in
     `git branch -a --no-merged <loop base>` is unmerged work the tracker does not
     name. Note them with commits ahead; do not read their diffs.
3. **Tracker.** The standard layout is `.scratch/<feature>/` with `spec.md`, one ticket
   per file under `issues/`, and optionally `ledger.md`. Ticket filenames vary by repo
   (`NN-slug.md`, `KEY-N-slug.md`, …); read `docs/agents/issue-tracker.md` for the repo's own convention when it exists.
   - Ticket status: match `\*{0,2}Status:\*{0,2}\s*(\S+)` in the first ~30 lines.
     Closed = `complete`, `resolved`, `wontfix`. Everything else is open
     (`open`, `claimed`, `blocked`, `ready-for-agent`, `ready-for-human`, `needs-*`).
   - `Priority:` and `Blocked by:` lines, when present, order the "next" list.
   - **`Stage:` wins over `Status:` when both exist.** A repo driven by the ticket-flow
     loop carries both: `Status:` is binary (open/resolved), `Stage:` is where in the
     loop the ticket actually is (`to-implement` | `implementing` | `to-review` |
     `reviewing` | `to-merge` | `done` | `blocked`). Closed = `done`. Report the
     `Stage` value, never the flattened `open`.
   - **Read headers in one pass, never one process per file.** A per-file process
     loop over hundreds of tickets hits the tool timeout on Windows. When the loop's base is the checked-out
     branch and up to date, one Grep over `.scratch/**/issues/*.md` for
     `Stage:|Status:|Priority:|Blocked by:|Deferral:` reads every header at once.
     For another branch, pipe the paths into one `git cat-file --batch` (each line
     `<branch>:<path>`) and parse the stream in a single script.
   - `ledger.md` is a recent-activity log. Column layout varies by repo and it may be
     a bare table (`date | ID | commit`) with no prose. Read the last rows for IDs and
     dates; cross-reference the IDs against `git log` to learn what each one was.
4. **Resolve blockers.** Build a table of
   every ticket: `ID | status | priority | blocked-by IDs`, across all features in one
   pass. Then, for each open ticket, look up the status of every ID in its
   `Blocked by:` line. A blocker that is closed does not block. A ticket is
   **unblocked** when it has no `Blocked by:` line or all of its blockers are closed.
   Do this lookup literally; do not infer cycles or ordering from the IDs alone. Expect
   1–4 unblocked tickets in a healthy tracker; zero means a dependency error worth
   naming.
   - **Accepted debt requires explicit deferral.** Use a `Deferral: accepted`
     record naming who accepted it, why and its integration/release impact.
     Missing Priority and directory names do not establish acceptance. An explicit
     runnable `Stage` with satisfied blockers remains work; a contradictory
     deferral marker requires correction, not silent removal from the queue.
     Genuinely deferred tickets are parked work, not queue.
5. **Git.** The refresh in step 2: if `git pull --ff-only` fails (no upstream,
   diverged branch, dirty tree), say so in one line and read the state as-is; never
   force, merge or stash to make it succeed.
   Then `git log --oneline -15 <loop base>` and
   `git log --oneline -10 <loop base> -- .scratch/` to find
   which features moved most recently and what closed. `git status --short` for a
   dirty tree. Ignore whole-tree CRLF noise (`--ignore-cr-at-eol` gives zero diff).
6. **Active feature** = the `.scratch/` dir with the most recent commits, not
   directory mtime. Skip commits that touch more than one feature dir (tracker
   migrations, header sweeps): they are housekeeping, not feature work. If every
   recently touched feature is fully closed, the active feature is the first one in
   dependency order with open tickets.

7. **Brief sources.** The merged PRs of the last ~7 days (`git log --since=<7 days
   ago> --merges --format='%ad %s' --date=short <base>`) say which features moved;
   the first lines of each moved or active feature's `spec.md` say what that feature
   is; for open tickets, the title and the "why it is parked" section (whatever the
   repo calls it) say what is left and why it waits. Read only those parts, not the
   whole spec. Milestones past the tracker (the next units, the release, what waits
   until after it) come from the roadmap or plan docs the project instructions name,
   and from the user's memory when it records those decisions.

Never read closed tickets' bodies for the brief; they are history, not state.

## Output

Portuguese if the repo's docs are in Portuguese, otherwise English, headers included.
Two shapes:

- **Ticket blocks** when `foreman` runs this as its step 1 or the user asks for the
  tickets (`/standup tickets`, "which tickets"): the shape in [`tickets.md`](tickets.md).
- **Project brief** otherwise, below.

### Project brief

Written for a reader who does not track ticket IDs: no ticket IDs, no hashes. Name
features, units and parts of the product the way the repo's docs do. Every line is a
short bullet, one idea, at most two lines. Under 30 lines, no preamble.

**Where we are**: 2–4 bullets. What moved in the last week, as what the product can
now do; whether anything is running now; repo hygiene (dirty tree, local base behind
its remote, stale branches) in one bullet, only when there is any.

**Next steps**: a numbered list, in order. First the steps that close the current
milestone (unit, feature, phase), each one a product step that groups its tickets
("finish the houses of chapters 23–25", never one line per ticket). Then the
milestones after it, up to the release and what waits until after it. Each item: the
step in bold, then what it involves and what it waits on (a human decision, a review,
a device check). When steps come from outside the tracker (step 7), close the list
with one line saying which.

**Parked**: one bullet per item parked on purpose: what, why, and what would bring
it back (a decision, a threshold, a review). Accepted debt goes here.

End with one line: the ticket queue is behind `/standup tickets`.

An empty tracker still gets the brief, with next steps from step 7's sources; when
those name nothing, offer three concrete options (code audit, bug hunt against a named
area, new feature from the spec) rather than inventing work.

## When the repo does not follow the layout

If there is no `.scratch/` and project instructions name no tracker: report the last
5 commits and the dirty tree (**Where we are** becomes one bullet on what those
commits did), then say in one line that there is no issue tracker to
read and point at the `.scratch/<feature>/issues/` one-file-per-ticket convention. Do not guess
next steps from diffs.

