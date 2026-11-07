# Stage 2: implement test-first

Read with `SKILL.md`, the loop's owner. These are the rules stage 2 works under.

**`Status: needs-triage` is triaged first, on the loop's base, before any branch.**
A review opens follow-ups that way (`ticket-shape.md`); nobody has triaged them yet.
Read the ticket, its origin and the code it names, then decide alone: write the
contract in the ticket's shape, or close it as `wontfix` (no real defect, or a
cleanup that reads no better than what it replaces). Design, taste or an
irreversible call goes to the proxy once, for the whole ticket ("Asking the proxy"):
an `Escalate` ends at `blocked` as usual. Record the outcome under `## Comments`
as `Triage by the driver: <outcome> — <reason>`, set `Status: ready-for-agent` or
`Status: wontfix` (with `Stage: done`), and commit on the loop's base. `wontfix`
stops there; `ready-for-agent` carries on below, as any ticket would.

**Each red/green cycle separates tests from production.** The load-bearing check is
the separation in the commits, not any agent's promise, and under the driver a
script makes it: every commit stage 2 adds is test-only or production-only, or the
handoff is parked. Test files are the usual test paths plus the binding's
`Test files:`; the tracker is metadata, allowed in either. Whoever writes the tests
does not make them pass in the same commit, and stage 2 does not touch test files
in a code commit. Later test-only commits and harness corrections are valid:
each relevant cycle records its own red/green proof. Reason: green tests once sat on top of a broken
parser, exercising a copy of the logic.

**A committed test wrong in its harness is fixed, not escalated.** Timing, a
broken helper, a mutant the criteria cannot tell apart from the real code: fix
the test in its own test-only commit, prove it red again for the right reason
(against the base, or by mutating the production code), and say what was wrong
under `## Comments`. A surviving mutant that no criterion can separate is recorded
as equivalent, with the reason. Only a test that shows the criteria themselves
cannot hold stops stage 2.

**A committed test asserting behaviour a criterion replaces is updated, not
escalated.** It was right under the old contract; the ticket retires that
contract. Its file counts as a test-only Primary file even when stage 1 did not
list it. In its own test-only commit, change only what the replaced behaviour
forces: how the test reaches the behaviour, or an assertion that states the old
behaviour, which takes the criterion's new one. Every assertion on behaviour the
ticket keeps stays byte-for-byte. Prove it red by mutating the production code,
and name each updated test under `## Comments`.

**Stage 2 reads around its change before the red test.** List the callers of every
function it changes and the degenerate inputs the change itself creates (an empty
set, a singular system, a value at the boundary), and give a test to any of them
the change could break. A regression is a reopen whatever the criteria say.


**Red-green proof before reporting.** Show that the new tests fail without the
change and pass with it. Every bug
fix has a test that would fail without it, and that test calls production code,
never a copy of it.

**Criteria check before the gate.** About half of all stage 3 findings are a
numbered criterion the code plainly misses. When the last cycle is green, hand a
subagent with fresh context (your runtime's own subagent tool, in the foreground, the stage's model)
the ticket and `git diff <merge-base>..HEAD`, read-only, with one question per
numbered criterion: which production line meets it, and which test fails
without that line. Every criterion it cannot point at is a miss: close it with
another red/green cycle, then ask again about those criteria alone. Record the
check under `## Comments` as one line per criterion (✅ with `file:line`, or what
was fixed). A runtime without a subagent tool answers the same questions itself
and says so in that line.

Hand off at `to-review` with gate evidence (`SKILL.md`, "Gate evidence at handoff").
