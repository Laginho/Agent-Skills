# Bindings block for a repo without one

Ask for the two values, write the block where it belongs, then get on with the
work. Do not copy this skill into the repo — one copy of the standard is the point.

    ## Bindings do fluxo (skill `ticket-flow`)

    - Gate: `<command that runs typecheck + lint + tests>`
    - Base branch: `<name>`
    - Test files: `<regex>`
    - Sync gate: `<command>` (optional: a fuller gate the foreman runs once per session, at the sync)
    - PR gate: `<command>` (optional: a fuller gate `pr-review-loop` runs once per PR, before approval)

Models are not a repo binding: the lineups are global, in `sweatshop/lineups.md`,
and the driver refuses a `Models` line in a repo's block. The lineup's reviewer has
to be enough for any ticket; the more expensive reviewer is kept for the
`Review: human` PR and for pre-release audits.

`Test files:` is optional: a regex for test fixtures kept beside production code,
which a test-only commit may touch. The usual test paths need no line.

Tracker paths and ticket shape do **not** go in this block. They are already in
`docs/agents/issue-tracker.md`.
