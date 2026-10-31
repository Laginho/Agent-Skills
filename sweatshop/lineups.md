# Lineups

The models every repo's ticket flow runs on: one `Models (<name>):` line per lineup,
`Models (default):` naming the one a run takes without `-Lineup`. Repos keep only
`Gate:` and `Base branch:` in their bindings; a `Models` line there is refused.

- Models (default): terra
- Models (terra): stage 2 gpt-6.1-terra xhigh, hard gpt-6.1-terra xhigh, stage 3 gpt-6.1-sol xhigh
- Models (sol): stage 2 gpt-6.1-sol high, hard gpt-6.1-sol xhigh, stage 3 gpt-6.1-sol xhigh
- Models (opus): stage 2 opus-5.5 high, hard opus-5.5 xhigh, stage 3 opus-5.5 xhigh

Terra implements on xhigh: on high it ended 5 of 32 stage-2 runs early or with a broken
handoff in P-Chess's v0.1.0 build, against 0 of 11 on xhigh and 0 of 33 for sol high (2026-10-31).
