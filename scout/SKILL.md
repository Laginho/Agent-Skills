---
name: "scout"
description: "Says which sweatshop lanes can start now, side by side with the ones already running: work ready in the folder, no driver on it, no file overlap. Read-only; launches nothing. Use when asked \"can I start another lane\", \"what can run in parallel\", \"scout\", or with /scout."
---

# Scout

Answer one question for the current repo: which lanes (`sweatshop/SKILL.md`,
Lanes) can start now. Read-only apart from `git fetch`; launches nothing. Each lane
gets its own `foreman` session, which the human opens.

Run from the main checkout, on the machine that runs the drivers: check 3 reads a
named mutex, which another machine cannot see, so from there every lane looks idle.
Language follows `standup`'s rule.

## Checks

Checks 1 and 2 hold for the whole repo: when one fails, it is the first line of the
answer and every lane waits on it, but still list the lanes so the human sees what
would start once it is fixed. Checks 3 to 5 are per lane, a lane being a tracker
folder with an `issues/` directory; the first that fails is its reason.

1. **Base pushed.** Once, before any lane: `git fetch --prune`, then
   `git rev-list --count origin/<base>..<base>`. Above zero, no lane can start: its
   clone starts from origin and would miss those commits.
2. **No session without a lane.** An unmerged `sweatshop/<stamp>` (no lane segment)
   refuses every lane until its PR is merged. Push the base first (check 1), then
   merge: merged the other way round, the local base diverges from origin and
   `pull --ff-only` fails. Say whether the PR merges clean:
   `git merge-tree --write-tree <base> <session>` (exit 1 and `CONFLICT` lines).
3. **Not running.** The lane's clone is `.artifacts-build/lanes/<folder>` (the
   repo's binding may say otherwise). Its driver holds a named mutex while it runs:

       if (Test-Path <clone>) { Set-Location <clone>; $n = 'sweatshop-repo-' + ((Get-Location).Path.ToLower() -replace '[\\/:]', '_'); try { [Threading.Mutex]::OpenExisting($n).Dispose(); 'running' } catch { 'idle' } } else { 'idle' }

   A lane-less driver on the main checkout shows the same way, with the main
   checkout as the path; it refuses every lane.
4. **Work ready.** Read tickets as `standup` does (loop's base, ticket branches via
   `ticket-state.ps1`); the lane's loop base is its open `sweatshop/<folder>/*`
   session, else the base. Ready = a `to-review`, or a `to-implement` whose
   `Blocked by` are all `done` on that loop base. A blocker done only on another
   lane's unmerged session still blocks.
5. **No overlap.** Compare `Primary files` (ticket-flow) of this lane's open tickets,
   except `blocked` and `ready-for-human`, with those of every running lane and of
   every other lane you are about to recommend. The run goes on to dependents as
   they unblock, so all open tickets count, not only the ready ones. Same file:
   overlap. Same directory only: possible overlap. A ticket without
   `Primary files`: unknown. Overlap or unknown is not a refusal: name the tickets
   and paths, and the human decides.

## Output

One line per lane, launchable first:

    api        can start: 3 ready (API-004, API-007, API-010); no overlap
    web        can start, with overlap: WEB-002 and API-007 touch src/auth/session.ts
    docs       running (driver alive in its clone)
    billing    nothing ready: 4 open, all wait on API-010

Then, for each launchable lane, the line the human pastes into a new session:
`/foreman lane <folder>`. Two lanes that overlap each other: recommend one, name the
other as "after that one". Missing clone: say the foreman creates it.

Under 15 lines. No preamble.
