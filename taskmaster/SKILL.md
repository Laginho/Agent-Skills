---
name: "taskmaster"
description: "Runs several sweatshop lanes at once through their foremen — one foreman per one or two lanes, syncs relayed between them when a lane's PR merges, one digest at the end. Use when asked to run several lanes, \"taskmaster\", or with /taskmaster."
---

# Taskmaster

You run several `sweatshop` lanes (`sweatshop/SKILL.md`, Lanes) through their
foremen. Each `foreman` owns its lanes: watching, summary, report, sync. You own
what sits between foremen. Read `foreman/SKILL.md` sections 5 and 9 first: they
are what you relay and digest.

Your context holds foreman reports and PR state only; stage output stays with
the foremen, so your session lasts the whole shift.

Language follows `standup`'s rule.

## 1. Lanes

The lanes the request names. None named: run `scout` and take the lanes it says
can start. A repo-wide refusal from scout (base not pushed, a session without a
lane) stops you with scout's answer.

## 2. Spawn the foremen

Two lanes that overlap each other run in sequence: start the one scout
recommends; the other waits for step 3's scout rerun. Group the rest in twos; an
odd one runs alone. Launch one child task per group, all at once, each one that
reports back to you when it ends (T3 Code: `delegate_task`), with the prompt:

    Use the foreman skill on lane <a> and lane <b> in <repo>.

Then end your turn; the reports wake you.

## 3. Between reports

- **A foreman ends:** keep its final message whole for the digest; in chat, one
  line per lane: `<lane>: done, PR <url>`.
- **The human says a lane's PR merged:** every other open lane syncs (foreman
  section 9). A foreman still running gets the message `Lane <x> merged: sync
  your lanes once their drivers stop.` A foreman that ended: spawn a child with
  `Use the foreman skill to sync lane <y> with the base (section 9) in <repo>.`
  Then run `scout` again: lanes that a merge unblocked go back to step 2.

## 4. Digest

When every foreman has ended, one message, then notify:

- **Your call:** every lane's `Needs your call` and `Review: human` lines, each
  prefixed with its lane, and every **Your turn** line.
- **PRs:** one line per lane: PR link, tickets done, report PDF when there is one.
- **Merge order:** from the main checkout, after `git fetch`,
  `git merge-tree --write-tree origin/<base> origin/<session>` per open lane PR.
  Clean ones first; a conflicting one names its files. After the first merge the
  rest may need a sync, which step 3 handles.
- **Cost:** the foremen's costs summed per model across lanes, `?` rows counted
  apart. API list price, as in foreman section 5.

Done when every lane from step 1 has a digest line or a stated reason it did not
run.
