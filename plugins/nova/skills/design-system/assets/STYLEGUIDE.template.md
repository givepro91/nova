# Design System — STYLEGUIDE

> The contract for all UI work in this repo. Layout, color, typography, spacing, radius,
> elevation, motion, component selection, and UX behavior follow this document.
> Values live **once**, as named tokens in the canonical source (see below) — reference them
> by role, never hardcode a new value when a documented token covers the role.
> **Fill every `‹…›` with this project's real values. Delete guidance blockquotes when done.**

**Canonical token source:** `‹path to the token file — the single source of every value below›`
**UI primitives live in:** `‹path to component primitives, if any›`

---

## Color

Reference tokens by role, not hue. Define a light and a dark value for each.

| Role | Token | Use |
|---|---|---|
| Background | `--color-bg` | page base |
| Surface | `--color-surface` | cards, panels |
| Border | `--color-border` | dividers, outlines |
| Text | `--color-text` | primary body text |
| Muted text | `--color-text-muted` | secondary/captions (must pass AA) |
| Primary | `--color-primary` | main action / brand |
| Accent | `--color-accent` | secondary emphasis |
| Success / Warn / Danger | `--color-success` / `--color-warn` / `--color-danger` | status |

> Contrast: body and muted text must meet WCAG AA (4.5:1) in **both** themes.

## Typography

- **Font stack:** `‹system stack — e.g. -apple-system, "Pretendard", sans-serif›` (no webfont CDN; system fallback required).
- **Scale** (`--text-*`): `‹xs / sm / base / lg / xl / 2xl …›` with line-heights.
- **Weights:** body `‹400›` · emphasis `‹600›` · display `‹700›`.
- **Roles:** display · title · body · caption · code — each maps to a scale step + weight.

## Spacing & layout

- **Space scale** (`--space-*`): `‹4 · 8 · 12 · 16 · 24 · 32 · 48 …›` — use steps, never arbitrary px.
- **Container / grid:** `‹max width, columns, gutter›`.
- **Breakpoints:** `‹sm / md / lg›`.

## Radius & elevation

- **Radius** (`--radius-*`): `‹sm / md / lg / full›`.
- **Elevation** (`--shadow-*`): `‹a small, fixed set of tiers›` — don't invent a new shadow; pick a tier.

## Motion

- **Duration** (`--dur-*`): `‹fast / base / slow›`. **Easing** (`--ease-*`): `‹standard / decel›`.
- Always honor `prefers-reduced-motion: reduce` (no non-essential motion).

## Component selection

- Prefer the existing primitives in `‹primitives dir›`. `‹Which component for which role — button variants, inputs, dialog, etc.›`
- Don't build a new component when a primitive covers the need; extend the primitive instead.

## UX behavior

- **Focus:** every interactive element has a visible keyboard focus ring.
- **States:** define default / hover / active / disabled / loading / empty / error for interactive surfaces.
- `‹Any project-specific interaction rules — toasts, form validation timing, etc.›`

---

## Resolution order (when this guide is silent)

When a case isn't covered above, resolve in this order — never invent inline:

1. **Reuse a documented token / pattern** that already covers the role.
2. **Match the nearest documented sibling** (the closest role/component that *is* specified).
3. **Follow the platform / framework default** for the stack.
4. **If genuinely novel**, propose an addition to this guide (a new token + its role) rather than hardcoding a one-off value — then use it.
