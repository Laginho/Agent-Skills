# Stage 3: review and merge

Read with `SKILL.md`, which owns the loop: dispatch, the ticket shape, gate
evidence and the proxy. These are the rules stage 3 works under. A fix stage 3
writes itself follows stage 2's red-green proof (`stage2.md`).

**Stage 3 reviews against the written contract, every finding in one pass.**
A reopen is earned by one of three things: a numbered criterion the code does
not meet, a Primary-files or test-first rule broken (under the driver a script already
checked the test/production split of stage 2's commits; otherwise inspect every
commit's `git diff --stat`: test-only red cycles alternate with production-only
changes, with ticket metadata allowed in either), or a regression — the
change broke something that worked before it. A requirement the criteria do not
state is none of these, however sensible: it becomes a `CLEAN-*` ticket and the
review approves on the criteria as written. Stage 3 never rewrites a criterion's
text; only stage 1 does. Read the whole diff before writing the verdict. In the first review block,
record the affected callers, failure paths and cross-feature interactions examined,
and any not examined; the numbered criterion verdicts remain the acceptance record.
List every finding in that verdict — a finding held back for the next pass costs a
full stage-2 cycle. A re-review checks the ❌ items and the diff since the last
review; a new finding in code the previous pass already read is named as that
pass's miss.

**Every confirmed unresolved finding has an open destination or an explicitly
accepted deferral.** On an open ticket it goes under `## Comments`; on a closed
ticket, create/link an open follow-up or record who accepted deferral, why and
integration/release impact. A comment on a closed ticket alone is not scheduled
work. Link the original ticket for history. Only stage 1 moves a comment into the body, and
when it does it adds the file to Primary files and a numbered criterion. An
unfolded comment is a note, not a requirement: prose in a body that no file and no
criterion backs is invisible to stage 2, which will ship green without it.

**Small fix, or back to stage 2.** Comments, stale documentation and tiny obvious
corrections inside Primary files may be fixed in review. Meaningful production
behavior authored during review, including test-exempt tickets, gets a fresh
independent review of the added diff before approval. Prefer reopening to stage 2
for behavioral repairs needing new tests or source outside Primary files; if a
reviewer already wrote such a repair, preserve it and hand it to another reviewer.
Record author, independent reviewer, examined diff and verdict in Resolution.

**Documentation the change made stale is a small fix wherever it lives.** A
comment, an ADR or a design note that now describes the old mechanism changes no
behaviour and needs no test: stage 3 corrects it in its own fix commit instead of
opening a `CLEAN-*` ticket.

**Reopening.** A review that knocks down a closed ticket sets
`Stage: to-implement`, marks which criterion fell (❌ with the reason), removes the
ledger line, and appends a review block saying what is left. The block's
verdict line is `Verdict: Reopen — <what fell>`: the driver counts those lines,
and the second one makes the driver park the ticket for the foreman to diagnose
the cause before retrying (foreman, section 2). The next stage 2 still uses the
`hard` implementer when configured; that escalation does not settle a contract
gap or an earlier review miss.

## Closing

Stage 3 closes by appending a `#### Resolution (YYYY-MM-DD)` block to the ticket —
decision, files, red-green proof, gate output — and adding the ledger line, in the
same commit as `Stage: done`. **The ticket is the memory between sessions.**

The review's **verdict** is one line, and it is the first line of the Resolution
block: `Verdict: Approve`, or `Verdict: Needs your call: <one sentence why>`.
The findings follow. "Needs your call" is for anything the reviewer is not
confident about, including a small fix it made itself that it would rather have
a human glance at. A wrong "Approve" costs more than a held ticket.

Merge depends on the loop's base:

**Into a session branch** (a `sweatshop/*` is open):

1. Rebase the ticket branch onto the session. Verify gate evidence for that code;
   reuse the green run if no production changed during rebase or review.
2. A conflict inside the ticket's Primary files: resolve it. Outside them:
   `Stage: blocked` with the conflict under `## Comments`, commit, stop.
3. `git checkout <session>; git merge --no-ff <ticket branch>`, then the
   Resolution block, the ledger line and `Stage: done` in one commit on the
   session. No PR, no push: the driver pushes and opens the session PR when the
   run stops, every verdict in its body. `Review:` holds nothing here.

**Into the bindings' base** (no session), always through a PR:

1. Rebase onto the base; verify gate evidence, push, `gh pr create`.
2. Post the review as one PR comment, verdict first.
3. `Review: agent` and the verdict is `Approve`: wait for CI
   (`gh pr checks --watch`), then `gh pr merge --merge --delete-branch`, pull the
   base branch, set `done` there with the ledger line. Never squash.
4. `Review: human`, or the verdict is `Needs your call`: set `to-merge`, leave
   the PR open, stop.
