# Lineups

One `Models (<name>):` line per lineup; `Models (default):` names the one a run
takes without `-Lineup`.

- Models (default): terra
- Models (terra): stage 2 gpt-6.1-terra xhigh, hard gpt-6.1-sol xhigh, stage 3 gpt-6.1-sol xhigh
- Models (sol): stage 2 gpt-6.1-sol high, hard gpt-6.1-sol xhigh, stage 3 gpt-6.1-sol xhigh
- Models (opus): stage 2 opus-5.5 high, hard opus-5.5 xhigh, stage 3 opus-5.5 xhigh
- Models (hydrogen): stage 2 gemini-4-hydrogen xhigh, hard gemini-4-hydrogen xhigh, stage 3 gpt-6.1-sol xhigh

Terra implements on xhigh: on high it ended 5 of 32 stage-2 runs early or with a broken
handoff (P-Chess v0.1.0), against 0 of 11 on xhigh.

Hard goes to sol xhigh in the terra lineup: Terra matched Sol on normal tickets at about a
third of the cost but stopped early or asked again and again on long review-type tickets.
A repo routes a ticket type to Sol by binding its `Difficulty: hard` rule, not with `Models`.

Hydrogen is on trial (Bruno, 2026-11-13): Gemini 4 Hydrogen implements in place of Terra,
on the Antigravity plan, so stage 2 spends no Codex quota. It takes the hard tickets too, to see
whether it holds up on them; Sol keeps the review.
