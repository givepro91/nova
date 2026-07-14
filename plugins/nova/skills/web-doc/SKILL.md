---
name: web-doc
description: Build a polished, self-contained HTML *document* — a report, write-up, prep doc, RCA, notes, or showcase page meant to be read, shared, or kept — by choosing a style that fits the document's character instead of defaulting to one look. Produces ONE portable .html file — inline CSS, system fonts, no CDN or external assets (CSP-safe), light + dark, accessible. Ships three editable starting styles (notion / report / editorial) and hands off to /design-direction when the look is genuinely subjective. Trigger when the user wants prose or data turned into a page — "make this a web page", "as an HTML doc", "share as a page", "페이지로 만들어줘", "웹 문서로 만들어줘", "도식화해서 보여줘".
when_to_use: When the user wants a STANDALONE HTML document to read, share, or keep — a write-up, report, analysis/RCA, notes, prep doc, or showcase/landing — and the content already exists or is being written. If the look-and-feel is subjective and vague, route to /design-direction first, then return here to build. NOT for application UI / React components (that's implementation work) and NOT for a session worklog (use /worklog).
argument-hint: "[what document + optional style: notion | report | editorial]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# /web-doc — turn content into a document, not a template

A document deserves a style pitched at what it *is* — a reading doc, an analysis, a showcase — not the one look you reach for every time. Reusing a single template (or a claude.ai-style landing hero for everything) is the tell that no choice was made. This skill picks a **fitting** style from the document's character, builds **one self-contained HTML file**, and only escalates to a full design decision when the look is genuinely subjective.

This is the **build** sibling of `/design-direction` (which *decides* a subjective look by showing options). Here the character usually determines the style outright, so you build directly; when it doesn't, you hand off.

## Principle

- **Character picks the style.** Classify what the document is before choosing how it looks. Most documents fall cleanly into one of the three styles below — pick and build.
- **One portable file.** Output is a single `.html`: CSS inlined in `<style>`, **system fonts**, **no CDN / webfont / external asset** (works offline, survives a strict CSP, and matches Nova's self-contained rule). Embed any image as a `data:` URI.
- **Both themes, always.** Ship light + dark via `prefers-color-scheme` **and** a `:root[data-theme]` override so a manual toggle wins. Give the second theme real care, not a naive invert.
- **Tooling is pluggable, not fixed.** The three styles are *starting points*, not law. For look-and-feel guidance use whatever design skill is best available (`frontend-design`, or something better) — never hardcode one tool. When the ask is subjectively vague ("make it modern/sleek/premium"), that is `/design-direction`'s job, not a guess here.
- **Words are design material.** Write from the reader's side. A style carries a document; it doesn't excuse vague copy.

## The three styles — character → style

| Style | Document character | Signature | Home skeleton |
|---|---|---|---|
| **notion** (default) | Read quietly: notes, write-ups, prep docs, knowledge | Sidebar TOC · `<details>` toggles · calm callouts | `styles/notion.css` |
| **report** | Diagnose / persuade: analysis, RCA, incident, data-integrity | Sticky top tabs (🙂 plain / 🔬 deep) · evidence boxes · severity chips | `styles/report.css` |
| **editorial** | Show & be remembered: showcase, portfolio, proposal, landing | Hero · strong display type · big stats · scroll reveal | `styles/editorial.css` |

One-line chooser: *quiet reading → notion · diagnose a problem → report · make an impression → editorial.* When unsure between two, prefer the calmer one (notion).

## Procedure

1. **Classify the character.** Name what the document is and its single job. Map it to a style above. If the user named a style, use it.
2. **Subjective look? Route first.** If the request is about *feel* and the words are vague ("modern", "세련되게") rather than about a document *type*, run `/design-direction` to settle palette/type/layout by showing options, then come back and build with the locked direction.
3. **Build from the style.** Inline the chosen `styles/*.css` into a `<style>` block and follow that style's skeleton (below). Use the user's **real content** throughout — never lorem, never gray boxes. The page body must never scroll sideways: wrap wide tables/code/diagrams in an `overflow-x:auto` container.
4. **Hold the quality floor** (non-negotiable):
   - `<html lang="…">` + `<meta charset="utf-8">` + responsive viewport meta.
   - Self-contained: no external fetch/font/script/style. System font stack only.
   - Light + dark, both cared for. AA contrast on body and muted text in **both** themes.
   - Visible keyboard focus; `prefers-reduced-motion` respected; escape `<`/`>` inside code.
5. **Verify by seeing it.** Open the file in a browser (a local `http.server` + a screenshot, since `file:` is often blocked) and check both themes and any toggles/tabs actually render — don't claim it works from the source alone.

## Style skeletons

**notion** — `.wrap` = sticky `.side` (`.nav` TOC) + `main`; sections as `.p-title`; each item a `<details class="q"><summary>…</summary><div class="body">…</div></details>`; callouts `<div class="cb evi|hon|cs"><span class="t">label</span><p>…</p></div>`.

**report** — `.rpt-head` + `<div class="tabs">` (`.tab[data-tab]`) + `<section class="pane" data-pane>`; evidence `<div class="ev"><b>근거</b> …source…</div>`; severity `<span class="sev crit|warn|ok">`. Tab-switch JS is a ~6-line listener (commented at the bottom of `report.css`).

**editorial** — `.hero` (`.display` + `.tagline`) + `.block` sections; big numbers `<div class="stat"><span class="num">…</span><span class="cap">…</span></div>`; optional `.reveal` scroll-in via IntersectionObserver.

## Relation to other Nova skills

- **`/design-direction`** decides a *subjective* look by showing mockups; `/web-doc` *builds* a document whose style its character already implies. Vague feel → design-direction; clear document type → web-doc.
- **`/worklog`** renders a *session worklog* deterministically (Nova-branded). `/web-doc` authors *arbitrary* documents in a fitting style. Don't use web-doc for worklogs or worklog for general docs.

## Pitfalls

- **One look for everything.** A landing hero on a quiet reading doc, or plain notes styled as a pitch — the style must fit the character.
- **External assets.** A Google-Fonts `<link>` or CDN script silently fails under CSP and breaks offline. Inline everything; system fonts only.
- **Dark theme as an afterthought.** A naive invert kills contrast. Define both theme token sets.
- **Guessing a vague vibe** instead of routing to `/design-direction`.
- **Claiming it renders without opening it.** Toggles, tabs, and dark theme are exactly what breaks silently — see it before you ship it.
- **Hardcoding a tool.** "Always use X for design" is the anti-pattern this skill exists to avoid. Pick the best available; keep it swappable.

## Success criteria

- The style visibly fits what the document *is* — a stranger could guess the document type from a thumbnail.
- One self-contained `.html`: opens offline, passes a strict CSP, renders in light and dark, keyboard-navigable.
- Real content throughout; wide content scrolls inside its own box, never the page.
- Verified by actually viewing it, both themes.
