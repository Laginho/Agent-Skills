# Stage 2: implement test-first

Read with `SKILL.md`, which owns the loop: dispatch, the ticket shape, gate
evidence and the proxy. These are the rules stage 2 works under.

**Each red/green cycle separates tests from production.** The load-bearing check is
the separation in the commits, not any agent's promise, and under the driver a
script makes it: every commit stage 2 adds is test-only or production-only, or the
handoff is parked. Test files are the usual test paths plus the binding's
`Test files:`; the tracker is metadata, allowed in either. Whoever writes the tests
does not make them pass in the same commit, and stage 2 does not touch test files
in a code commit. Later test-only commits and harness corrections are valid:
each relevant cycle records its own red/green proof. This rule exists because green tests have sat on top of a broken
parser — the tests were exercising a copy of the logic.

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
change and pass with it. Report the real suite counts, not rounded ones. Every bug
fix has a test that would fail without it, and that test calls production code,
never a copy of it.

Hand off at `to-review` with gate evidence (`SKILL.md`, "Gate evidence at handoff").
Stage 2 stops the moment `to-review` is committed; it does not review its own work.
