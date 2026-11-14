# Standup: ticket blocks

The ticket-level output, for `foreman` step 1 or a user who asks for the tickets.
Same facts as the brief (SKILL.md steps 1–7), five short blocks, plain prose or
one-line bullets, no headers wider than this, under 40 lines:

**Done**: the last 2–3 closed tickets or ledger entries, feature-level, with IDs and
dates. Tickets only: no commit hashes, no housekeeping commits (step 6).

**In progress**: claimed/in-progress tickets, an open sweatshop session with its
commits ahead, unmerged branches the tracker does not name, plus a dirty working tree
if any.

**Open**: count of open tickets per feature, and the count must equal the number of
open ticket files you saw; genuinely deferred tickets counted separately (step 4);
name the top 3 by priority/dependency order.

**Unblocked**: the open tickets as a tree, indented under what blocks them, so the
reader gets the queue *and* why the rest waits. Roots are the tickets whose blockers are
all closed — that is the work queue. Under a `blocked` or `to-merge` node, add the last
`## Comments` line: it is the question waiting on a human. On a repeat (a ticket with
several blockers) print `ID ...` rather than re-expanding it.

```
DEP-006       to-review
  DEP-001     blocked
  > axios 1.20 declares ...
    QA-001    to-implement
CLEAN-003     to-implement
```

This block is mandatory. Accepted debt stays out of it (step 4).

**Next step**: one recommendation: the first open, unblocked ticket in dependency
order, with its path. If nothing is open: say the tracker is empty and offer three
concrete options (code audit, bug hunt against a named area, new feature from the
spec) — do not invent tickets.
