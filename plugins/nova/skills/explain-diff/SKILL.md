---
name: explain-diff
description: Build a rich, interactive HTML explainer of a code change — a working diff, commit, branch, or PR — so a human actually *understands* it (enough to build the next change on it), not just approve it. Fixed pedagogical arc → background · intuition (toy data + HTML diagrams) · literate code walkthrough · a comprehension quiz you must pass before shipping. Produces ONE portable .html (inline CSS, system fonts, no CDN, light + dark, accessible). Trigger when the user wants a change explained or understood — "explain this diff/PR", "이 변경/PR 설명해줘", "리뷰용 해설 만들어줘", "understand this change", "explain-diff".
when_to_use: When the user wants to *understand* a code change (not merely read the raw diff) — a working diff, commit, branch, or PR — before reviewing, shipping, or building on it. Produces a self-contained HTML explainer ending in a comprehension quiz. NOT for a session worklog (use /worklog) and NOT for an arbitrary document (use /web-doc).
argument-hint: "[what to explain: a commit / branch / PR ref, or the working diff]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# /explain-diff — understand a change, don't just approve it

Reading a diff line by line is not the only way to understand code — and it is a bad one. As agents write more of the code, the bottleneck moves from *writing* to *understanding*, and you understand not just to **verify** (👍/👎) but to **participate**: to hold enough of the system in your head to propose the next change. This skill turns a change into the explainer a great teammate would write for you — **background → intuition → a literate walkthrough → a quiz** — as one self-contained HTML file.

The quiz is the point, not decoration. It is a **speed regulator**: the human-understanding counterpart to `/gate` (which audits the *agent's* claims). Rule of thumb — *don't ship or approve a change until you can pass its quiz.*

> Inspired by Geoffrey Litt's "Understanding is the new bottleneck" / `explain-diff`. Nova's take drops the Notion variant (portability, see CLAUDE.md #6) and bakes the quality floor into a shipped skeleton.

## Principle

- **Explain to participate.** Teach the *existing* system first, then the change — enough that the reader could propose what comes next, not just tell right from wrong.
- **Fixed arc, tailored content.** The four sections are fixed; the diagrams and examples are re-derived from *this* change every time. Pick a **small family of diagrams** and reuse it — a simplified UI, a data-flow, a labeled bar — with **example data** in them. Never ASCII diagrams (HTML/CSS only).
- **One portable file.** Output is a single `.html`: inline `styles/explain-diff.css` in a `<style>`, **system fonts**, **no CDN / webfont / external asset** (works offline, survives a strict CSP — Nova's self-contained rule #6). Embed any image as a `data:` URI.
- **The quiz gates understanding.** Five medium questions — hard enough that you must grasp the substance, but no gotchas. Options are **shuffled at render** and correctness keys off a flag, so the answer can't be picked by its length or slot. Feedback per option; result via **text + `aria-live`**, not color alone.
- **It's a reading artifact, not a committed doc.** Write it **outside the repo**, date-prefixed, so it stays out of version control (like a printout you read then discard).

## Procedure

1. **Resolve the change and its surroundings.** Get the diff, then read *around* it — the background needs the system that was already there, not just the changed lines.
   ```sh
   git show <ref>                       # a commit
   git diff <base>...<head>             # a branch / range
   gh pr diff <n> ; gh pr view <n>      # a PR
   git diff                             # the working tree
   ```
   Use `Read`/`Grep`/`Glob` to explore the files the diff touches and the ones it depends on. If the target is ambiguous (which ref? working tree vs a PR?), ask before building.
2. **Draft the four sections** (see skeleton). Order the code walkthrough as a *story*, not alphabetically. Write in clear Korean by default (match the user), engaging and plain — the [prose-lint spirit](../worklog/SKILL.md) applies: no 420-char walls, no `→→` chains, no `x·y·z` list-dumps.
3. **Assemble one self-contained HTML.** Inline `styles/explain-diff.css` (it carries the layout, both themes, a11y, and the reference JS in a trailing comment — copy that JS into a `<script>` and fill `QUESTIONS`). Use the change's **real content and real code**; escape `<`/`>` inside `<pre>`.
4. **Hold the quality floor** (non-negotiable, same as `/web-doc`):
   - `<html lang="…">` + `<meta charset="utf-8">` + responsive viewport meta.
   - Self-contained: no external fetch / font / script / style. System font stack only.
   - Light + dark, both cared for; AA contrast on body and muted text in **both** themes.
   - Visible keyboard focus; `prefers-reduced-motion` respected; `<pre>` uses `white-space: pre`/`pre-wrap`; wide code/tables scroll inside their own box, never the page.
   - Quiz: options shuffled, correct slot varies, option lengths balanced; score `role="status"`, per-answer `aria-live`.
5. **Write it outside the repo, date-prefixed, and verify by seeing it.**
   ```
   ~/explanations/YYYY-MM-DD-explanation-<slug>.html      # or /tmp, or a path the user gives
   ```
   Open it (a local `http.server` + a screenshot, since `file:` is often CSP-blocked) and confirm **both themes**, the scroll-spy/TOC, and that clicking quiz options actually scores — don't claim it renders from the source alone.

## The four sections (skeleton)

Structure: `header.hero` (title + `.meta` chips) → `.layout` = `main` + `aside.rail` (sticky scroll-spy TOC) → `#prog` progress bar. Right after the hero, a **`.tldr` card**: the single strongest sentence first, so the change lands before any background.

1. **Background** — `<h2 id="bg">`. A deep, skippable primer for newcomers (lead with a `.skip` callout linking to §직관), then a narrow background aimed straight at the change. Teach the components the change touches, with a `.flow` diagram if data moves between them.
2. **Intuition** — `<h2 id="intuition">`. The essence, not the details: a `.note` one-liner, concrete **toy data**, and one reusable diagram family (`.flow` / `.tally` / `table.tax`). Answer "why is it built this way?", not just "what changed".
3. **Code** — `<h2 id="code">`. A literate walkthrough in story order: `<h3>` per step, prose around each `<pre>` snippet, grouped so the reader sees the shape before the lines.
4. **Quiz** — `<h2 id="quiz">`. `<div id="quiz">` (built by the reference JS) + a sticky `#score` + an `aria-live` `#live` + a hidden `#gateline` shown on a perfect score. Five medium MC questions drawn from the substance of the change.

## Relation to other Nova skills

- **`/gate`** audits the *agent's* completion claims (is the work real?). `/explain-diff`'s quiz gates the *human's* understanding (do you actually get it?) — the two are the agent-side and human-side of the same honesty loop.
- **`/worklog`** renders a *session* record deterministically (Nova-branded template). `/explain-diff` teaches *one change* with a fixed pedagogical arc. Different artifact, different question.
- **`/web-doc`** builds an *arbitrary* document in a style fitting its character. `/explain-diff` is the special case where the character is fixed (a change explainer) — so it ships one skeleton instead of choosing a style.

## Pitfalls

- **Explaining only the diff.** Without the surrounding system the reader can verify but not participate. Teach what was already there first.
- **ASCII diagrams / wall-of-diff code.** Use the HTML diagram families; order code as a story with prose between snippets.
- **Guessable quiz.** If the correct answer is always the longest or always slot B, the quiz measures nothing — keep options shuffled (the skeleton does this) and balance their lengths.
- **Templated feel.** The arc is fixed but the *content* — diagrams, toy data, examples — must be specific to this change.
- **Claiming it renders without opening it.** Dark theme, scroll-spy, and quiz scoring are exactly what breaks silently — see it before you ship it.
- **Committing the artifact.** It's a personal reading file; keep it out of the repo (write it elsewhere, date-prefixed).

## Success criteria

- A newcomer to this code could read it top to bottom and then **pass the quiz** — and feel ready to propose the next change, not just approve this one.
- One self-contained `.html`: opens offline, passes a strict CSP, renders in light and dark, keyboard-navigable, with the reusable diagram family carrying the intuition.
- Real content and real code throughout; wide content scrolls inside its own box; verified by actually viewing it in both themes.
