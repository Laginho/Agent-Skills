# Why the ticket-flow rules read as they do

The runs behind the rules, kept out of `SKILL.md`, `stage2.md` and `stage3.md` so
the rules stay short and carry no dates. When a run changes a rule, add its line
here.

- **Numbered criteria (stage 1).** Measured 2026-10-01: PHY-45 criterion 2 (no length jump at the wrap switch) could not hold, and it took a reopen and a `Proxy decided` to rewrite it.
- **A committed test wrong in its harness.** Measured 2026-09-30: four of fifteen stage-2 runs stopped on the old wording; the proxy answered all four without the human, three of them with exactly this fix.
- **A committed test asserting replaced behaviour.** Measured 2026-10-27: UI-012 stage 2 blocked on eight such tests; the proxy allowed exactly this edit, citing CLEAN-001 and CLOCK-001 as the same answer.
- **Stage 2 reads around its change.** Measured: APP-025 (2026-09-29) broke a caller one grep away; PHY-41 (2026-09-30) turned two collinear ropes into a singular system. Both reopened, both `S2-implícito`.
- **Documentation the change made stale.** Measured 2026-10-01: three docs-only `CLEAN-*` tickets for ADR-0004 cost 20% of a run, a full stage-2 and stage-3 cycle each.
- **Stage 3 reviews every finding in one pass.** Measured 2026-09-24: SYN-010 took two extra cycles (52% of its time) for findings that were all visible in the first pass, two of them new requirements.
- **Nothing in the background.** Measured 2026-09-24: a PHY-23 review backgrounded the gate and ended at `to-review` two minutes in.
- **Only the script's line is a proxy line.** Measured 2026-09-30: a Codex stage 2 (PHY-43) wrote two `Proxy decided` lines for decisions no proxy had made. Measured 2026-10-15: a Codex stage 2 (CONT-014) wrote two through a `/root/proxy` subagent on the stage's model. Codex stages could not reach the Claude card at all (measured 2026-10-29: inside the Codex sandbox the nested `claude` call hangs), so the proxy became one script with receipts, and the driver answers for runtimes that cannot reach it.
