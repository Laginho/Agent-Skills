---
name: grill-proxy
description: Grilling with a stand-in human — the `proxy` agent answers the routine questions of each round, and only design, taste and irreversible calls reach the human. Use when ticket-flow stage 1 grills, or when the user asks for a grill through the proxy or with /grill-proxy.
---

# Grill through the proxy

Run the `grilling` skill as written, with one change: **each round goes to the
proxy before it goes to the human.** `grilling` is vendored, so never edit it to
fit this; what this skill adds is defined here.

## Each round

1. Build the round as `grilling` says: the whole frontier, numbered, each
   question with your recommended answer.
2. **Spawn the `proxy` agent once for the whole round**, not once per question.
   Give it the plan being grilled, every decision already settled (and who
   settled it), the round itself, and the rule below, word for word. It answers
   one line per question: `Q<n> Decision: <answer> — <reason>` or
   `Q<n> Escalate: <why>`.
3. Show the human only the escalated questions, in the `grilling` format. Under
   them, list what the proxy settled, one line each:

       Answered by the proxy (reply with a number to override):
       - Q2 — <title>: <answer> — <reason>

4. Nothing escalated? Show that list and go straight to the next round, without
   waiting. The human can still override any line later.

An override replaces the proxy's answer and reopens every decision downstream
of it.

## The rule the proxy gets

> Escalate a question when it is a design decision (seams, module boundaries,
> interfaces, data model, the slicing of the work), a matter of taste or
> preference with no answer the evidence settles, or a change that is
> irreversible or expensive to undo (deleted data, a published API, a schema
> migration, anything outward-facing). Escalate when unsure. Decide everything
> else, and give the reason in one line.

This is broader than the loop's rule in `ticket-flow`'s "Asking the proxy",
which lets the proxy take design calls. Here the human is present, so design
stays theirs.

## What stays the same

- **Facts are still yours.** Look them up with an exploration sub-agent, as
  `grilling` says. The proxy decides; it does not research.
- **The human closes the session.** When the frontier is empty, list every
  decision the proxy made in one block and wait for the human to confirm the
  shared understanding. Nothing is acted on before that.
- **No proxy, or a runtime that cannot spawn one** (Codex): plain `grilling`,
  every question to the human. Never answer a question yourself and present it
  as the proxy's.
