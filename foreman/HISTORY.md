# Why the foreman rules read as they do

The runs behind the rules, kept out of `SKILL.md` so the rules stay short and
carry no dates. When a run changes a rule, add its line here.

- **Launch the driver detached.** Measured 2026-10-03: a background task's timeout killed the driver mid-review; on 2026-10-02 one had lived 10 h.
- **The check-in clock.** Measured 2026-09-24: a `/loop` check-in never fired and nobody noticed for 30 minutes.
- **Keep notes in a file.** Measured 2026-09-30: a Claude Code restart mid-run lost nothing because the notes held the launches, the pinned refs and the owed report.
- **Never hold run-log.md open.** Measured 2026-09-24: a `tail -F` lock crashed the driver twice.
- **Push only the session branch and the base.** Measured 2026-10-11: one `git push origin EDIT-001` tacked onto a commit stopped the run overnight.
- **Merge the run log, never copy over it.** Measured 2026-10-02: a copy over it would have deleted 38 rows.
- **A merging review can hide a miss.** Measured 2026-10-02: Opus 5.5 xhigh did this on 4 of 5 merges and the scoreboard read 0 %.
- **Close codex exec's stdin.** Measured 2026-10-02: 10 minutes lost waiting on stdin.
- **Report build.** Measured 2026-10-01: a `codex update` deleted the bundled Tectonic.
