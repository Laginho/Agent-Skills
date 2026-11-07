# Foreman report: build and content

Read from `SKILL.md` section 7 when a run owes a PDF report.

- **Build:** any LaTeX engine on the PATH (`tectonic -X compile <file>.tex`).
  The preamble loads `fontspec`, not `inputenc`/`fontenc`: Tectonic is XeTeX, and the T1
  font drops — and … (measured 2026-10-31).
  Recompile until there are no overfull-box warnings. None: Codex's bundled
  Tectonic under `~/.codex/.tmp/`, which a `codex update` can delete. Still none: commit the `.tex`, say so in the summary, and offer to
  download Tectonic from its GitHub release into a folder on the PATH.
- **Shape:** two parts. The front, at most two pages, is what the human reads:
  the chat summary's three blocks (`SKILL.md` section 5), **What was done**, the roadmap
  image, and the one thing that went wrong with its numbered recommendations.
  Everything else goes after the LaTeX `\appendix`, in a part titled `Registro`, for
  debugging and for comparing runs: timeline, per-stage table (minutes, tokens,
  cache, output, cost, outcome) with a chart of where the input went and what was
  wasted, comparison with the previous runs from `run-log.md`, observations per
  model, driver and runtime issues, restarts and cleanups, what you noticed and
  left alone, every `Débito humano:` line of the run, **Reopen attribution**,
  **Scoreboard**, and every `Proxy decided` line of the run's tickets, quoted per
  ticket and grouped by who decided (the model in its parentheses; a line without
  `(<who>)` is legacy, unknown). Count apart the ones the driver answered for a
  runtime that could not reach the proxy (its `proxy from <runtime> sessions` line
  in the `.out`), and list apart an older proxy line with no receipt, written by
  the stage's own model: that is the stage's judgement. The newest report in
  `docs/relatorios/` is the template for the appendix's sections, so runs compare
  side by side.
- **What was done:** in the front part, one short paragraph per ticket the
  run worked on, for a reader who never opened the tickets (a ticket's title and
  criteria are too abstract and too specific). Say what changes for whoever uses
  the product, the main file, and for each reopen what was broken, its cause and
  the file, as in "BUG-001: the scroll broke below 854x480; a hard-coded
  `set_size` in `render_ui.py` caused it." Sources: the ticket on the session
  branch, its merge diff and the review findings (`SKILL.md` section 6), never memory.
  Tickets of one kind (content drafts) can share a paragraph with a line each.
- **Roadmap image:** when `AGENTS.md` has a `Roadmap:` binding, the per-session
  roadmap as this run left it goes right after **What was done**. On the
  session branch, run the binding's per-session command, render its SVG to
  `docs/relatorios/<report>-roadmap.png` as the binding says, and
  `\includegraphics` it. Then restore the files the command wrote
  (`git checkout -- <files>`) before committing anything: they are tracked, and
  every lane would conflict on them. Commit the PNG with the `.tex` and `.pdf`.
  A generator that fails means no image: quote its error in the report and go on.
- **Codex quota:** next to the cost per model, the percentage of the weekly
  Codex quota each Codex model spent, from `sweatshop/scripts/codex-quota.ps1
  -Tracker <tracker> -Since <launch> -Until <last row>`. Split a model that
  played two roles (hard implementer and reviewer) by stage. Name the plan, say
  the total is exact while one stage is ±1 point (Codex rounds to integers), name
  any Codex thread that ran outside the stages (it shares the quota), and say so
  when the weekly window reset mid-run. Claude models get `--`.
- **Reopen attribution:** `SKILL.md` section 6's rows for this run as a table (ticket, round,
  finding, label, why, and who judged it when it was not you), the totals per label,
  and the review-miss and churn cases. Separate session-review, release-audit and
  post-release discoveries, retaining unknown origins. Place it before the scoreboard, since the
  scoreboard reads them.
- **Scoreboard:** a section with the output of `sweatshop/scripts/scoreboard.ps1`,
  run over every repo on this machine that has a `<tracker>/run-log.md` (this run's
  repo and its siblings), with `-Latex`, pasted as printed: it prints booktabs
  longtables (the preamble loads `longtable` and `makecell`). Never the Markdown
  in a `verbatim` block: it runs off the page. Never a lane's clone: after the
  copy-back it holds the whole history, and every row would count twice. It is cumulative, not this run's alone:
  it is how the human picks lineups from real tickets instead of a dedicated
  benchmark. Compare it with the previous report's scoreboard and name the rows that
  moved. Read it under three rules:
  - A reopen rate belongs to the implementer → reviewer pair. Compare implementers
    only under the same reviewer, and reviewers only over the same implementer.
  - A pair under 10 reviews is an anecdote. Say so next to any conclusion drawn from it.
  - A row without an effort (`sonnet`, `gpt-6-luna`) predates the effort column.
    Never fold it into a row that has one.
  - Judge an implementer by the `S2 rate`, not the raw reopen rate: a reopen with no
    S2 finding was the spec's or the reviewer's. While `Unclassified` is above zero
    the S2 rate is a floor. `S1` counts in the findings table point at stage 1,
    `S3 noise` at the reviewer. Read `Fixed in review for S2` beside the S2 rate:
    a reviewer that fixes instead of reopening shows a low rate and a high fixed
    count, and the implementer's misses are the two added together.

  Read the evidence table as counts within recorded coverage, not defect rates.
  Compare human rescues separately from routine approvals, proxy decisions and
  automatic recoveries. `Shutdown s` is sampled runtime-completion to process-exit
  delay, including forced shutdown; `?` is unmeasured, never zero. Preserve missing
  history as unknown rather than comparing it with newly instrumented runs.

  A recommendation to change a lineup names the scoreboard rows it rests on.
- **Numbers come from the logs, never from memory:** `run-log.md` rows, the
  stages' `.txt` (Codex: `turn.completed` usage), `git log` of the session. A
  count you did not recompute from them does not go in. When a row's outcome
  lies (the driver read a stale copy), say so and report what really happened.
