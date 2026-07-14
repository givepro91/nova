---
name: design-system
description: Set up a portable design-system *contract* a coding agent will actually obey — a STYLEGUIDE.md (roles + a resolution order for when it's silent), one canonical token source, and a binding rule wired into the repo's agent file — so UI work uses documented tokens instead of inventing values. Owns the structure; delegates the subjective look (palette, type personality) to /design-direction or frontend-design. Stack-adaptive and framework-neutral — never installs a framework or component library. Trigger when the user wants to establish / set up / scaffold a design system for a project — "set up a design system", "디자인 시스템 잡아줘", "give this project a styleguide + tokens", "make our UI consistent".
when_to_use: When a project needs a design-system CONTRACT that agents follow — a STYLEGUIDE, canonical design tokens, and a rule binding agents to them — rather than a one-off look. Routes to /design-direction first when the subjective look (hues, type feel) is still unsettled. NOT for deciding a vague aesthetic (that's /design-direction), NOT for a standalone HTML document (that's /web-doc), and it does not install frameworks or scaffold components.
argument-hint: "[app/ui path (optional) · locked direction if any]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# /design-system — set up a contract agents obey, not a palette

A design system that changes how agents build isn't a color list — it's a **contract**: a STYLEGUIDE that names roles, **one canonical token source**, and a **rule that binds agents to both**. This skill sets up that structure so any agent (or session) styles a new screen from documented tokens instead of inventing values. It owns the *structure* and hands the *subjective look* to `/design-direction` / `frontend-design`.

This is the **build** counterpart to the project-specific "Design System" rule — the reason such a rule can exist is that this scaffold puts a STYLEGUIDE + tokens in place for it to point at. It pairs with `/claude-md`: this writes the *project-specific* binding rule into the free area / preamble; `/claude-md` keeps the universal managed block lean.

## Principle

- **A contract, not a palette.** The deliverable is a *system agents follow* — STYLEGUIDE (roles) + canonical tokens + a binding rule — not a set of hex values. If an agent can't style a new screen from what you left behind without asking, the contract is incomplete.
- **One canonical token source.** Every color / space / type / radius / elevation / motion value lives **once**, named by role. The binding rule forbids inventing a new value when a documented token already covers the role.
- **Portable, stack-adaptive.** Detect the stack and emit tokens in its idiomatic place and format; **never install a framework or component library** (Nova is a public, portable artifact — plugin users may not use your stack). Framework-neutral CSS custom properties by default; system-font fallback, no webfont-CDN assumption.
- **Structure here, look delegated.** This skill decides roles, scales, and the resolution order — **not** the subjective hues or type personality. If the palette / type feel is unsettled, route to `/design-direction` (or `frontend-design`) to lock it; until then, fill tokens with clearly-marked neutral placeholders. Keep the design tool pluggable — never hardcode one.
- **Silence has an answer.** The STYLEGUIDE ends with a **resolution order** (what to do when it doesn't cover a case) so agents follow a documented fallback instead of freelancing.

## Procedure

1. **Detect stack & existing assets.** Scan `package.json` / config for the UI stack (plain CSS, Tailwind, CSS-in-JS, a token pipeline) and for any existing tokens/theme file, `docs/STYLEGUIDE*`, or component-primitive dir. **If a STYLEGUIDE or tokens already exist → audit & extend, never clobber** (idempotent, like `/claude-md`).
2. **Decide token home & format** from the detected stack — a plain `tokens.css` of custom properties, a Tailwind `theme` extension, a `tokens.json` feeding the existing build, etc. Adapt placement to what's idiomatic; **install nothing**.
3. **Subjective look unsettled? Route first.** If hues / type personality aren't decided and the user's words are vague, run `/design-direction` (or `frontend-design`) to lock palette + type by showing options, then return. If already locked (user gave a direction), use it. If still open, use neutral placeholders marked *replace via /design-direction*.
4. **Write the contract.** Start from `${CLAUDE_PLUGIN_ROOT}/skills/design-system/assets/STYLEGUIDE.template.md` → `docs/STYLEGUIDE.md` (or the repo's docs home). Fill the role sections (color · typography · spacing/layout · radius · elevation · motion · component selection · UX behavior) with the project's **real** values, and complete the final **resolution-order** section. No lorem, no gray boxes.
5. **Write the canonical tokens.** Start from `${CLAUDE_PLUGIN_ROOT}/skills/design-system/assets/tokens.css` (or the stack's format) as the single source; map every documented role to a named token. Include a dark set via `prefers-color-scheme` + a `[data-theme]` override.
6. **Bind agents to it via `/claude-md`.** Add the project-specific Design-System rule into the **free area / preamble — NOT the managed block**: "All UI work follows `docs/STYLEGUIDE.md`; use the tokens in `<canonical file>` (the canonical source); don't invent a color / size / shadow when a documented token covers the role; when STYLEGUIDE is silent, follow its resolution order; UI primitives live in `<dir>`." (This is exactly the project-specific boundary `/claude-md`'s Notes calls out.)
7. **Confirm, then verify.** Blast radius is large (new files + a governing rule), so **state the plan — which files, which rule — and get a yes before writing.** After writing, confirm each documented role resolves to a real token, and note that re-running audits/extends rather than clobbers.

## Relation to other Nova skills

- **`/design-direction`** *decides* the subjective look by showing mockups; `/design-system` sets up the *structure + contract* and routes to it when the look is open. Vague feel → design-direction; "give us a system agents follow" → design-system.
- **`/web-doc`** styles ONE standalone document; `/design-system` establishes a *project-wide* contract for application UI. Don't use one for the other.
- **`/claude-md`** owns the *universal* managed block (kept lean); `/design-system` writes the *project-specific* binding rule into the free area — the boundary `/claude-md`'s Notes names (design-system contracts don't belong in the block).

## Pitfalls

- **Installing a framework or component library** (shadcn, Tailwind, a UI kit). Portability forbids it — adapt to what's there; scaffold no components.
- **Deciding the subjective look here** instead of routing to `/design-direction` — this skill owns roles and scales, not hues and personality.
- **Dumping the Design-System rule into `/claude-md`'s managed block.** It's project-specific → free area / preamble only.
- **Tokens that don't cover the roles the STYLEGUIDE names**, so agents still invent values. Every documented role must map to a token.
- **A STYLEGUIDE with no resolution order** — then "silent" cases get freelanced.
- **Clobbering an existing STYLEGUIDE / tokens on re-run** instead of auditing and extending.

## Success criteria

- A stranger agent, given only `docs/STYLEGUIDE.md` + the token file + the binding rule, styles a **new** screen without inventing a value or asking — every role resolves to a documented token.
- Portable: no framework installed, system-font fallback, tokens in the stack's idiomatic place; works whatever the plugin user's stack is.
- The subjective look is either locked (via `/design-direction`) or the open tokens are clearly marked as placeholders — never silently guessed.
- Re-running audits and extends; it never clobbers existing design assets.
