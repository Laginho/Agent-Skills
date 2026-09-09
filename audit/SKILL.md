---
name: audit
description: Whole-repo code audit that ends in a verdict (Approved / Approved with cleanup / Not approved) and a written report in docs/audits/. Use when the user invokes /audit, optionally with a path to restrict scope.
disable-model-invocation: true
---

# Audit

Whole-repository quality audit. The product is a **verdict** and a **report**, the way a hired audit firm would deliver one. Repo-agnostic: assume nothing about stack, tracker, or conventions beyond what the repo itself documents.

Scope: the repo root, or the path given as argument. Always the whole scope, never a diff. Diff review belongs to `code-review`.

## The verdict is the product

A model asked to review will find something, because an empty report feels like failure. This skill exists to make **"Approved"** a legitimate outcome. Approval is credible only when the report shows what was checked and what was attempted to break. "Nothing found" without the attempt log is the failure mode.

Do not hunt for restructurings. Do not be "ambitious". If the code is direct, boring, tested and correct, say so and stop. Prefer a small number of high-conviction findings over a long list.

### Verdicts (fixed English words, first line of the report)

- **Approved**: no Broken, no Fragile findings.
- **Approved with cleanup**: no Broken, no Fragile; Slop findings exist.
- **Not approved**: at least one Broken or Fragile finding.

A verdict over partial coverage is written as `Approved (covered set only)`, never bare.

## Tiers

- **Broken**: wrong behavior, bug, security hole, data loss path, code that cannot run.
- **Fragile**: works today, breaks on a predictable change. No test suite at all or no runnable gate is Fragile. Silent catch-and-log, hidden coupling, untested critical path, documentation that contradicts the code, `any`/casts hiding an invariant at a boundary, non-atomic state updates.
- **Slop**: works, maintainability problem. Dead code, duplicated logic, thin wrappers and identity abstractions, single-implementation interfaces, feature logic leaking into shared paths, ad-hoc conditionals bolted onto unrelated flows, files over 1000 lines, bespoke helpers where a canonical one exists, hand-rolled stdlib, "temporary" branching.
- **Process** (separate section, never affects the verdict, except the two Fragile cases above): no tracker, no CI, no lint, no README, no contribution notes.

Style nits are never reported.

## Procedure

1. **Docs first.** Read README, CLAUDE.md, AGENTS.md, ARCHITECTURE.md, CONTRIBUTING, ADRs, and any file that states rules or architecture. These define the repo's *own stated bar*. Note the README's language.
2. **Previous audit.** If `docs/audits/` exists, read the latest report. Every previous finding gets a status in the new report: fixed, open, regressed.
3. **Map.** Inventory files, sizes, entry points, dependency edges, test layout, runnable commands (`package.json`, `Makefile`, `pyproject`, CI config). Delegate the sweep to a cheaper sub-agent if available; the judgment is never delegated. Read the source yourself; choose what to read from the map.
4. **Run the gate.** Typecheck, lint, tests, build, whatever the repo defines. Record commands and results. No runnable gate is a Fragile finding.
5. **Try to break it.** Trace the main flows end to end. Write throwaway tests in a scratch directory, never inside the repo. Launch the app only if a documented, credential-free way exists. Never touch external services, never use credentials. Record every attempt and its outcome.
6. **Verify each finding.** Before writing a finding, re-read the lines it cites. A false finding costs the reader more than a missed one. Distinguish "violates its own stated rules" from "violates the general bar"; the first is more damning.
7. **Write the report.**

Investigate and take notes in English. Write the final report in the README's language; verdict words stay in English.

## Coverage

Silent partial coverage is the worst outcome. The report lists what was read in full, read partially, and not read. If you could not read everything, say so and qualify the verdict.

## Report

Path: `docs/audits/<YYYY-MM-DD>-<short sha>.md`. One file per run, never overwrite.

Structure, nothing else:

1. **Verdict** and signature: `Verdict: <word>` then `Audited by <model name as you know it>`. No effort level.
2. **Summary**: five lines at most.
3. **Scope and coverage**: path audited, commit, files/dirs read in full, partially, not at all.
4. **Method**: gate commands run and results, break attempts and outcomes, app launched or not and why.
5. **Top 3**: the three highest-impact findings in full. Each: tier, `file:line`, what is wrong, why it matters (what breaks, when), proposed fix. Code in the fix only when prose would be ambiguous. Always exactly three when three or more findings exist.
6. **All findings**: one line each: `<Tier> file:line — one sentence`. Broken and Fragile always listed in full. Slop grouped by pattern with a count when repeated (`Slop 6× catch-and-log without rethrow: a.ts:12, b.ts:40, ...`). No cap; length is itself the message.
7. **Process**: process findings, one line each.
8. **Previous audit**: status of each prior finding, or "first audit".
9. **Recommended order**: what to fix first and why, short.

No tickets, no appendix, no diagrams.

## Tone

Direct and serious. Do not soften a Broken finding into a suggestion; do not inflate a nit into a blocker. If the codebase is solid, the report says so in one line and the rest is the evidence.

## Boundaries

Read-only on the repo except for the report file. Never edit source, never commit, never create tickets. Runs on whatever model invokes it; the signature is the only note about that.
