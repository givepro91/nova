---
name: design-direction
description: Decide subjective look-and-feel (visual style, color, layout, "vibe") by showing concrete options in a live browser, not by describing them in prose. When a request is aesthetic and underspecified ("make it modern / sleek / playful / premium"), words guess wrong and waste rounds. This skill renders 2–4 real mockups, lets the user click to react, then narrows by addressing the user's stated worry, tuning variants, and locking signature decisions (palette, type, layout) one at a time. Encodes the just-in-time companion offer, fidelity scaling, the click→read→narrow loop, and the pitfalls that make show-don't-tell go wrong.
when_to_use: When a design/UX decision is subjective and the user's words are vague — "modern", "sleek", "clean", "premium", "통통튀는", "세련되게", "make it pretty" — i.e. look-and-feel choices where seeing beats reading. Also when the user asks to redesign / re-skin / pick a color or layout and you would otherwise guess from adjectives.
argument-hint: "[what to decide — e.g. 'home hero style']"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# /design-direction — show, don't tell

Subjective visual decisions are settled by **seeing**, not by describing. "Modern", "sleek", "통통튀는" mean different things to you and the user; every adjective you trade is a guess, and a wrong guess on look-and-feel is expensive to walk back. So when the decision is aesthetic and the words are vague: **render real options, let the user react to pixels, and narrow from there.**

This is a *process* skill — it tells you HOW to drive the decision, not what to build. Pair it with implementation skills (frontend-design, etc.) once the direction is locked.

## Principle

- **A vague adjective is not a spec — it's a request to be shown options.** Don't expand "make it modern" into your own assumption and build it. Show 2–4 distinct readings of it and let the user point.
- **Pixels over prose.** A side-by-side of two real mockups resolves in one glance what three paragraphs of description cannot.
- **Narrow, don't restart.** Each round keeps what the user liked and changes only the thing in question. Broad direction → address their specific worry → tune variants → lock signatures. Never re-open a settled layer.
- **Real content, real references.** Use the project's actual copy, brands, and reference sites — never lorem ipsum or gray boxes. Placeholder content hides the very design problems you're trying to surface. If the user named a reference (a site, a product, a screenshot), reflect it faithfully — don't approximate from memory.
- **Match the user's taste profile.** Carry their stated preferences into every mockup (language, polish level, disliked patterns). A mockup in the wrong register wastes the round.

## Procedure

1. **Detect the decision.** Confirm it's genuinely subjective look-and-feel (style, palette, type, layout, motion feel) AND the user's words are vague. If the spec is already concrete ("use #5A4FE6, Inter, 2-col"), skip this skill and just build it.

2. **Pick a live-preview surface** (best available):
   - The brainstorming **visual companion** if present (a server that watches a dir and serves the newest HTML to the user's browser with click events) — preferred when available.
   - Else a **local static HTML** you write and the user opens in their browser (e.g. the project already runs a dev server — reuse its host).
   - Else publish the mockups (an artifact / shared page) and link it.
   The surface must let the user *see* the options; click-to-select is a bonus, terminal reply is always the fallback.

3. **Offer it just-in-time — its own message, only the offer.** Do NOT offer a browser preview upfront. Wait until a question genuinely reads better shown than told, then offer it then, alone (no clarifying question stapled on). On accept, open it. On decline, fall back to concrete text options with named references and don't offer again.

4. **Render 2–4 distinct options.** Not 1 (no comparison), not 6 (choice overload). Each option is a self-contained, polished mockup of the *same* content in a *different* aesthetic, so only the variable in question differs. **Scale fidelity to the question** — wireframe boxes for a layout question, real polish for a "which vibe" question. Label each option and give a one-line rationale. Make the selection mechanism obvious (clickable, or "reply A/B/C").

5. **Read the reaction.** Merge the user's terminal words with any click/selection events from the preview surface. The terminal message is primary; clicks reveal exploration (they may click several before settling — the pattern is signal too).

6. **Narrow — one layer per round, new screen each time:**
   - **Address the stated worry directly.** If they like A "but worry it's tiring on the eyes", diagnose the cause (luminance, saturation, contrast) and show A tuned to fix exactly that — keep the parts they liked. Don't jump to a different option.
   - **Lock signatures one at a time.** After the broad direction, settle the load-bearing specifics — palette / signature color, type, density — each as its own focused comparison (e.g. show a candidate accent applied in both light and dark, at small surface area).
   - **Never reuse a filename / re-litigate a locked layer.** Each screen is fresh; once a layer is locked, build on it.

7. **Return cleanly to the terminal.** When the next step is conceptual (architecture, scope, tradeoffs — text, not pixels), push a brief "continuing in terminal" screen so the user isn't staring at a resolved choice, and move the discussion back to text.

8. **Record the locked decisions.** State the final direction explicitly — layout, light/dark, signature color with hex, type — so it's captured and hard to second-guess. This is the handoff to implementation.

## Pitfalls

- **Offering the companion upfront**, or stapling a clarifying question onto the offer. It's its own message, fired only when a real visual question arises.
- **Describing in prose what you could show.** If you catch yourself writing a paragraph comparing two looks, render them instead.
- **Gray-box / lorem mockups.** They hide the real design issues. Use the project's actual content and any named references.
- **Restarting instead of narrowing.** When the user has a specific worry about an option they otherwise like, tune *that* option — don't throw it out and show new ones.
- **More than 4 options**, or only 1. 2–4.
- **Re-opening a locked layer.** Once the palette/layout is settled, don't quietly change it in a later mockup.
- **Guessing a named reference from memory.** If the user pointed at a site/screenshot, look at it and reflect it.
- **Leaving a stale resolved screen up** after the conversation moved on.

## Success criteria

- The user converged on a **concrete, locked** direction (layout + light/dark + signature color w/ hex + type) by reacting to things they actually saw — not to your description.
- The decision is one they're unlikely to reverse, because they compared real options.
- Each locked layer was settled in a focused round; no layer was re-litigated.
- The final direction is recorded explicitly and ready to hand to an implementation skill.
