# Ticket shape

Every writer of a ticket uses this shape: stage 1, a review opening a `CLEAN-*` or follow-up ticket, the foreman.

`to-tickets` publishes a local ticket as `# <NN>: title` with a
`**Status:** ready-for-agent` line and checkbox criteria. That is a triage queue
entry, and it cannot carry this loop: no address to cite in a commit, no field to
dispatch on, no declared boundary. **When stage 1 publishes to local files, write
this shape instead of that skill's template** — and change nothing else about how
that skill works. Its vertical slicing, blocking edges, expand–contract sequencing
for wide refactors and the approval quiz are why it is being called.

    # <AREA>-<NNN>: <Ticket title>
    Stage: to-implement
    Blocked by: <the ids that gate this one, or "none">
    Review: agent | human
    Difficulty: normal | hard
    Escaped-from: <the done ticket whose review let this bug through> (only on such bugs)

    - Primary files:
      - <path the ticket may touch> (<scope, when the whole file is not in play>)
      - New: <path>

    #### What to build

    The end-to-end behaviour this ticket makes work, from the user's
    perspective, not a layer-by-layer implementation list.

    #### Acceptance criteria

    1. <criterion, stated so a test can fail it>
    2. <criterion>

    #### Verification

        <the commands that prove it, gate last>

    ## Tests stage 2 writes (own commit, red)

    - <which file, at which seam, red for which reason before the change>

    ## Comments

Additions:

- **The id.** `<AREA>-<NNN>`, **unique across the whole repo** and **immutable** —
  it is the address every ledger line, commit message and review block cites. The
  filename keeps the vendor's positional prefix as well
  (`<NN>-<ID>-<slug>.md`): the number is dependency order and may go stale, the id
  never does. Reuse a prefix already in use before inventing one; next number is
  the highest existing for that prefix anywhere in the tracker, plus one
  (`grep -rhoE 'BUG-[0-9]+' <tracker> | sort -t- -k2 -n | tail -1`). A ticket that
  turns out to belong to another area keeps its id and says so in its body.
- **`Primary files`.** `to-tickets` says to keep file paths out of a ticket because
  they go stale. True of prose; this list is not prose, it is the boundary — the
  implementer may touch those files and nothing else. Keep it to the files in
  play, never an implementation plan. The ADR or doc that describes a mechanism
  the ticket changes is in play. So are the tests that assert behaviour a
  criterion replaces: grep for them while writing the ticket and list them,
  marked test-only.
- **Numbered criteria**, not checkboxes, so a review can fail "criterion 5" by name.
  Each one satisfiable: before publishing, check every criterion against the
  others and against the physics or spec it rests on.
- **`Review:`.** Who clicks merge. `agent` (the default when the line is missing)
  lets stage 3 merge an approved PR itself; `human` holds the PR for the person.
  Stage 1 sets it when writing the ticket — the author decides what they want to
  see, not the reviewer. Inside a session branch (`SKILL.md`, "Dispatch on a bare ID") nothing is held: `human`
  only puts the ticket at the top of the session PR.
- **`Difficulty:`.** Which implementer the driver sends: `hard` gets the lineup's
  `hard` model, `normal` (the default when the line is missing) gets stage 2's.
  Stage 1 sets `hard` when a first pass is likely to miss: criteria that interact,
  numerical or concurrent logic, a function many callers lean on. In doubt, write
  `normal`; the driver escalates any ticket after its second reopen anyway. A
  ticket that looks harder than `hard` is two tickets: slice it again.
- **`Escaped-from:`.** Set by whoever files a bug in behaviour a `done` ticket
  shipped and its stage 3 approved: that ticket's id. It marks an escape, a bug
  review let through, and these tickets become the stage 3 reviewer's eval set.
  Bugs no done ticket's criteria or diff covered carry no line.
- **A follow-up a review opens.** `Status: needs-triage` with `Stage: to-implement`,
  and whatever of the shape the review already knows: the driver's next stage 2
  triages it before building (`stage2.md`). One generation only: when the ticket
  under review carries a `Triage by the driver:` line, its follow-ups get
  `Stage: blocked` instead, with the reason, and wait for the human.
