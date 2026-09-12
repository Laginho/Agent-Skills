# Agent Skills

Three skills for coding agents. Provider-agnostic: a skill is a folder with a
`SKILL.md` inside, which is all any tool needs.

| Skill | What it does |
| --- | --- |
| [`audit`](audit/SKILL.md) | Whole-repo code audit ending in a verdict — Approved / Approved with cleanup / Not approved — and a written report under `docs/audits/`. Read-only except the report. |
| [`standup`](standup/SKILL.md) | Project-state brief: what got done, what is open, what to pick up next. Reads the repo's local tracker (`.scratch/`) and git. Read-only, answers in chat. |
| [`ticket-flow`](ticket-flow/SKILL.md) | The one-ticket-at-a-time build loop: stage 1 specifies, stage 2 implements test-first on a branch named for the id, stage 3 reviews and merges. Dispatches a bare ticket id on its `Stage:` line. Needs a repo with a local tracker (`docs/agents/issue-tracker.md`) and a bindings block in `AGENTS.md`. |

All three are user-invoked (`/audit`, `/standup`, `/ticket-flow` or a bare ticket id), never fired automatically.

## Install

**Instructions for the agent doing the install.** The user pointed you at this
repo; do these four steps.

### 1. Get the files

```
git clone --depth 1 https://github.com/Laginho/Agent-Skills
```

### 2. Review before installing

A skill is instructions you will later execute, so read before you copy. Read
both `SKILL.md` files in full and confirm each one still matches this
description:

- no scripts, no network calls, no reading credentials or environment tokens
- no `allowed-tools` in the frontmatter (that grants tools without asking)
- writes limited to what the table above says — `audit` writes its report,
  `standup` writes nothing

If any of that has changed, stop and tell the user what you found instead of
installing.

### 3. Copy each skill folder into your tool's skills directory

The folder name is what the user types as `/<name>`, so keep `audit` and
`standup` as-is.

| Tool | Directory |
| --- | --- |
| Claude Code (global) | `~/.claude/skills/` |
| Claude Code (one repo) | `.claude/skills/` in that repo |
| Codex | `~/.agents/skills/` |
| Antigravity | `~/.gemini/antigravity/skills/` or `~/.gemini/config/skills/` (its docs disagree; check which exists) |

Not listed? Use whatever directory your tool documents for skills. If it has
none, the two `SKILL.md` files still work as plain Markdown you read on demand.

Copy with `cp -r audit standup <dir>/` or, on Windows PowerShell,
`Copy-Item audit,standup <dir> -Recurse`.

### 4. Report back

Tell the user which skills installed, where, and how to invoke them. Two things
to mention when true:

- If the skills directory did not exist before now, the running session may need
  a restart to notice it.
- If a skill of the same name was already there, say so rather than silently
  overwriting — see Collisions below.

## Copy or link

Copying takes a snapshot: `git pull` here will not update what your tool runs,
and the two copies drift. To keep them live, symlink instead — `ln -s` on
macOS/Linux, or a junction on Windows, which needs no admin rights:

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\.claude\skills\audit" -Target "<clone>\audit"
```

Removing a link later: delete the link itself, never `rm -r` / `Remove-Item
-Recurse` on it — recursive delete through a reparse point can take the target
with it.

## License

MIT.
