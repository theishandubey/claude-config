# DESIGN.md - shadcn/ui Design System for AI Agents

This file is the source of truth for how generated UIs and artifacts should look and feel. It follows the community DESIGN.md convention (theme, color roles, typography, components, layout, elevation, do/don'ts, responsive behavior, agent prompts) and encodes the shadcn/ui design language. It is framework-agnostic: rules are expressed as design tokens, CSS variables, and scales. Use it with React + Tailwind + shadcn/ui, plain HTML/CSS, or any framework. Tailwind class equivalents are given as optional shortcuts.

How to use this file: read Section 1 to understand intent, then treat Sections 2-11 as hard constraints and Section 12 as the working procedure. When you hit a case this file doesn't cover, decide using Section 1's rationale, not personal taste.

---

## 1. Visual Theme & Atmosphere

The look: quiet, precise, editorial. Near-black text on near-white surfaces (inverted in dark mode), generous whitespace, hairline borders, small type, subtle shadows. The interface should feel like a well-set technical document, not a marketing page.

Why it looks this way:

- Monochrome-leaning palette. The default theme is grayscale. Color (destructive red, chart hues) is rare and therefore meaningful. If everything is colorful, nothing is important.
- Hierarchy from structure, not decoration. Emphasis comes from spacing, type weight (400 to 500 to 600), and surface contrast, never from adding new colors or heavy shadows.
- Density: comfortable, not cramped. 14px UI text, 36px controls, 24px card padding. Compact enough for real product work, airy enough to breathe.
- Own the code. shadcn components are copied into the project, not imported as a black box. You may restyle any surface freely, but never alter the accessibility foundation (roles, focus, keyboard wiring). As of the shadcn/ui June 2026 changelog, new projects default to Base UI primitives, with Radix still supported via the `-b radix` flag.
- Composition over configuration. Build complex UI from small, predictable primitives with one shared token vocabulary.
- Semantic tokens, not raw values. Every color references a CSS variable so a theme change propagates everywhere and dark mode is free.

Always use the shadcn "new-york" style. Two historical visual styles existed, "default" and "new-york", and per the shadcn/ui `components.json` docs "The default style has been deprecated. Use the new-york style instead." Set `"style": "new-york"` in `components.json` when scaffolding, and never generate against the deprecated default style's conventions. All specs below reflect current new-york conventions in the Tailwind v4 era.

Tiebreaker rule: when unsure between two options, pick the quieter one (less color, less shadow, less motion, fewer font weights).

---

## 2. Color Palette & Roles

Colors use the `name` / `name-foreground` pairing. The base token is the surface color; the `-foreground` token is text/icons guaranteed readable on that surface. Example: `bg-primary text-primary-foreground`. Never mix a foreground with a surface it wasn't paired with.

Colors are defined in OKLCH: `oklch(L C H)` where L = lightness 0-1, C = chroma (0 = gray), H = hue 0-360. OKLCH is preferred for perceptual uniformity. HSL/RGB are acceptable fallbacks outside Tailwind v4.

### 2.1 Token roles (what each is FOR)

| Token | Role | Typical usage |
|---|---|---|
| `background` / `foreground` | App canvas and default text | Page shell, sections, body text |
| `card` / `card-foreground` | Elevated surface + content | Cards, panels, dashboard tiles |
| `popover` / `popover-foreground` | Floating surface + content | Popover, dropdown, context menu, tooltip |
| `primary` / `primary-foreground` | High-emphasis action/brand | Default button, active/selected states |
| `secondary` / `secondary-foreground` | Lower-emphasis filled action | Secondary buttons, supporting UI |
| `muted` / `muted-foreground` | Subtle surface + low-emphasis text | Descriptions, placeholders, helper text, empty states |
| `accent` / `accent-foreground` | Interactive hover/active surface | Ghost hover, menu highlight, hovered rows |
| `destructive` | Destructive/error emphasis | Delete buttons, invalid states |
| `border` | Default separators | Cards, tables, dividers |
| `input` | Form control borders | Input, textarea, select outline |
| `ring` | Focus rings | Any focusable control |
| `chart-1`..`chart-5` | Chart palette | Data visualization only |
| `sidebar-*` (surface, foreground, primary, accent, border, ring variants) | Sidebar-scoped tokens | Sidebar container and items |
| `radius` | Base corner radius | Derives the radius scale (Section 5) |

### 2.2 Light and dark values (default "neutral" theme, current values)

Place under `:root` (light) and `.dark` (dark). This is the canonical scaffold.

```css
:root {
  --radius: 0.625rem; /* 10px */
  --background: oklch(1 0 0);
  --foreground: oklch(0.145 0 0);
  --card: oklch(1 0 0);
  --card-foreground: oklch(0.145 0 0);
  --popover: oklch(1 0 0);
  --popover-foreground: oklch(0.145 0 0);
  --primary: oklch(0.205 0 0);
  --primary-foreground: oklch(0.985 0 0);
  --secondary: oklch(0.97 0 0);
  --secondary-foreground: oklch(0.205 0 0);
  --muted: oklch(0.97 0 0);
  --muted-foreground: oklch(0.556 0 0);
  --accent: oklch(0.97 0 0);
  --accent-foreground: oklch(0.205 0 0);
  --destructive: oklch(0.577 0.245 27.325);
  --border: oklch(0.922 0 0);
  --input: oklch(0.922 0 0);
  --ring: oklch(0.708 0 0);
  --chart-1: oklch(0.646 0.222 41.116);
  --chart-2: oklch(0.6 0.118 184.704);
  --chart-3: oklch(0.398 0.07 227.392);
  --chart-4: oklch(0.828 0.189 84.429);
  --chart-5: oklch(0.769 0.188 70.08);
  --sidebar: oklch(0.985 0 0);
  --sidebar-foreground: oklch(0.145 0 0);
  --sidebar-primary: oklch(0.205 0 0);
  --sidebar-primary-foreground: oklch(0.985 0 0);
  --sidebar-accent: oklch(0.97 0 0);
  --sidebar-accent-foreground: oklch(0.205 0 0);
  --sidebar-border: oklch(0.922 0 0);
  --sidebar-ring: oklch(0.708 0 0);
}

.dark {
  --background: oklch(0.145 0 0);
  --foreground: oklch(0.985 0 0);
  --card: oklch(0.205 0 0);
  --card-foreground: oklch(0.985 0 0);
  --popover: oklch(0.205 0 0);
  --popover-foreground: oklch(0.985 0 0);
  --primary: oklch(0.922 0 0);
  --primary-foreground: oklch(0.205 0 0);
  --secondary: oklch(0.269 0 0);
  --secondary-foreground: oklch(0.985 0 0);
  --muted: oklch(0.269 0 0);
  --muted-foreground: oklch(0.708 0 0);
  --accent: oklch(0.269 0 0);
  --accent-foreground: oklch(0.985 0 0);
  --destructive: oklch(0.704 0.191 22.216);
  --border: oklch(1 0 0 / 10%);
  --input: oklch(1 0 0 / 15%);
  --ring: oklch(0.556 0 0);
  --chart-1: oklch(0.488 0.243 264.376);
  --chart-2: oklch(0.696 0.17 162.48);
  --chart-3: oklch(0.769 0.188 70.08);
  --chart-4: oklch(0.627 0.265 303.9);
  --chart-5: oklch(0.645 0.246 16.439);
  --sidebar: oklch(0.205 0 0);
  --sidebar-foreground: oklch(0.985 0 0);
  --sidebar-primary: oklch(0.488 0.243 264.376);
  --sidebar-primary-foreground: oklch(0.985 0 0);
  --sidebar-accent: oklch(0.269 0 0);
  --sidebar-accent-foreground: oklch(0.985 0 0);
  --sidebar-border: oklch(1 0 0 / 10%);
  --sidebar-ring: oklch(0.556 0 0);
}
```

Note: in dark mode, `border` and `input` use translucent white rather than solid gray, so hairlines sit naturally on any dark surface. Available base presets include Neutral, Stone, Zinc, Mauve, Olive, Mist, and Taupe; Neutral (above) is the safe default.

### 2.3 Extending the palette (e.g. success/warning)

There is no built-in success/warning token. Add a semantic pair rather than reaching for raw `green-500`/`amber-500`, so the new color themes correctly in both modes:

```css
:root { --warning: oklch(0.84 0.16 84); --warning-foreground: oklch(0.28 0.07 46); }
.dark  { --warning: oklch(0.41 0.11 46); --warning-foreground: oklch(0.99 0.02 95); }
```

In Tailwind v4, register with `@theme inline { --color-warning: var(--warning); --color-warning-foreground: var(--warning-foreground); }`. In plain CSS just use `var(--warning)`. Every new token needs both `:root` and `.dark` values.

---

## 3. Typography Rules

- Font family: use the system font or San Francisco. The sans stack is `-apple-system, BlinkMacSystemFont, ui-sans-serif, system-ui, sans-serif`, which renders San Francisco (SF Pro) on Apple platforms, Segoe UI on Windows, and Roboto on Android. The mono stack is `ui-monospace, 'SF Mono', SFMono-Regular, Menlo, Consolas, monospace`. Do not load webfonts for UI text; a brand font a project already ships wins per the precedence rules, but the default is always the system stack. Set via `--font-sans` / `--font-mono`; apply on body with antialiasing.
- Weight discipline: live in 400-600. Build hierarchy by stepping 400 to 500 to 600, not by jumping to 700. Reserve 700+ for display/hero only. Rationale: small weight steps keep the page calm; bold everywhere reads as shouting.
- Sizes: `text-sm` (14px) is the default for UI component text; `text-base` (16px) for reading content. Secondary text is `text-muted-foreground`, not a smaller size.
- Tracking: headings `tracking-tight`; body normal.

### 3.1 Type scale (canonical shadcn typography)

| Role | Size / weight / tracking | Tailwind |
|---|---|---|
| h1 | ~36px (lg:48px), extrabold, tight | `scroll-m-20 text-4xl font-extrabold tracking-tight lg:text-5xl text-balance` |
| h2 | ~30px, semibold, tight, bottom border | `scroll-m-20 border-b pb-2 text-3xl font-semibold tracking-tight first:mt-0` |
| h3 | ~24px, semibold, tight | `scroll-m-20 text-2xl font-semibold tracking-tight` |
| h4 | ~20px, semibold, tight | `scroll-m-20 text-xl font-semibold tracking-tight` |
| p (body) | 16px, leading-7, spaced | `leading-7 [&:not(:first-child)]:mt-6` |
| lead | 20px, muted | `text-xl text-muted-foreground` |
| large | 18px, semibold | `text-lg font-semibold` |
| small | 14px, medium, tight leading | `text-sm font-medium leading-none` |
| muted | 14px, muted | `text-sm text-muted-foreground` |
| inline code | 14px, mono, muted surface | `bg-muted rounded px-[0.3rem] py-[0.2rem] font-mono text-sm font-semibold` |

Plain-CSS equivalents: h1 `font-size:2.25rem;font-weight:800;letter-spacing:-0.025em`; body `font-size:0.875-1rem;line-height:1.75`.

---

## 4. Layout Principles

- Spacing scale: 4px-based (Tailwind unit = 0.25rem). Use 4/8/12/16/24/32/48/64. Never invent off-scale values like 13px or 18px.
- Use `gap` for spacing between flex/grid children, not margins between siblings. Prefer `flex flex-col gap-4` over `space-y-4`. Rationale: gap keeps rhythm consistent and survives reordering.
- Common internal paddings: cards `p-6` (or `--card-spacing`), popover/dropdown content `p-1` to `p-4`, dialog `p-6`, page sections `px-4 md:px-6`.
- Containers: center content with a max width (`max-w-5xl mx-auto` for apps, `max-w-2xl` for prose). Full-bleed only for backgrounds.
- Alignment: left-align text and form labels. Center only hero/empty-state content.
- One primary action per view region. Everything else is secondary/outline/ghost.

---

## 5. Depth & Elevation

### 5.1 Radius scale (derived from `--radius`, default 0.625rem)
```css
--radius-sm: calc(var(--radius) - 4px);
--radius-md: calc(var(--radius) - 2px);
--radius-lg: var(--radius);
--radius-xl: calc(var(--radius) + 4px);
```
Convention: buttons/inputs `rounded-md`; cards `rounded-xl`; badges `rounded-md` or `rounded-full`; avatars/dots `rounded-full`. Changing `--radius` rescales the whole system, so never hardcode pixel radii.

### 5.2 Shadow scale
Elevation is signaled mostly by surface token + hairline `border`; shadows are a whisper on top. Low to high:
- `shadow-xs` - buttons, inputs, small controls (default resting elevation)
- `shadow-sm` - cards
- `shadow-md` - hover-raised cards
- `shadow-lg` - popovers, dropdowns, dialogs, floating surfaces

Never stack heavy shadows or use colored glows.

### 5.3 Standard control dimensions
- Button: default `h-9`, sm `h-8`, lg `h-10`, icon `size-9`; default padding `px-4 py-2`.
- Input / select trigger / textarea row: `h-9`.
- Badge: `h-5`, `px-2 py-0.5`, `text-xs`.
- Icons inside controls: `size-4` (16px); badge icons `size-3`.

---

## 6. Component Stylings

Each recipe lists anatomy, token-based style, and states. Tailwind strings are the canonical current classes; translate to plain CSS by resolving each utility to the matching variable/property.

Universal focus ring (all focusable controls): `outline-none focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px]`
Universal invalid: `aria-invalid:border-destructive aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40`
Universal disabled: `disabled:pointer-events-none disabled:opacity-50`

### 6.1 Button
Base: `inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-all shrink-0 outline-none` + universal focus/invalid/disabled. Icons auto-size to `size-4`.

Variants:
- default: `bg-primary text-primary-foreground shadow-xs hover:bg-primary/90`
- secondary: `bg-secondary text-secondary-foreground shadow-xs hover:bg-secondary/80`
- destructive: `bg-destructive text-white shadow-xs hover:bg-destructive/90 focus-visible:ring-destructive/20`
- outline: `border bg-background shadow-xs hover:bg-accent hover:text-accent-foreground`
- ghost: `hover:bg-accent hover:text-accent-foreground`
- link: `text-primary underline-offset-4 hover:underline`

Sizes: default `h-9 px-4 py-2`; sm `h-8 gap-1.5 rounded-md px-3`; lg `h-10 rounded-md px-6`; icon `size-9`.
States: hover = slight bg opacity shift; focus = ring; disabled = 50% opacity; loading = spinner + disabled.
Plain HTML: `<button>`/`<a>` with equivalent vars, 36px height, 6px radius, 12-16px horizontal padding.

### 6.2 Input / Textarea
`flex h-9 w-full min-w-0 rounded-md border border-input bg-transparent px-3 py-1 text-base md:text-sm shadow-xs transition-[color,box-shadow] outline-none placeholder:text-muted-foreground disabled:cursor-not-allowed disabled:opacity-50` + universal focus/invalid. Dark mode adds `dark:bg-input/30`.
Always pair with a `<label>` (`text-sm font-medium leading-none`). Never use placeholder as the only label. Link helper/error text via `aria-describedby`.

### 6.3 Card
Root: `bg-card text-card-foreground flex flex-col gap-6 rounded-xl border py-6 shadow-sm`; horizontal padding lives on children (`px-6`).
Anatomy: CardHeader (`grid gap-2 px-6`) with CardTitle (`font-semibold leading-none`) + CardDescription (`text-muted-foreground text-sm`); CardContent (`px-6`); CardFooter (`flex items-center px-6`).
Use the full composition; don't dump everything into content.

### 6.4 Dialog / Sheet / Drawer
Anatomy: trigger, portal, overlay, content, header (title + description), body, footer.
- Overlay: `fixed inset-0 z-50 bg-black/50` + fade.
- Content: `fixed left-1/2 top-1/2 z-50 grid w-full max-w-lg -translate-x-1/2 -translate-y-1/2 gap-4 rounded-lg border bg-background p-6 shadow-lg` + open/close animations.
- Title is REQUIRED for accessibility (visually hide with `sr-only` if not shown).
- Sheet = same primitive anchored to an edge (`inset-y-0 right-0 h-full w-3/4 sm:max-w-sm`).
- Never set manual z-index; overlays self-stack. Focus is trapped and restored by the primitive.

### 6.5 Dropdown Menu / Popover / Tooltip
- Content surface: `z-50 rounded-md border bg-popover text-popover-foreground shadow-md p-1` (popover `p-4 w-72` typical). Tooltip: `text-xs`, popover tokens or `bg-primary text-primary-foreground`.
- Item: `flex items-center gap-2 rounded-sm px-2 py-1.5 text-sm outline-none` with hover/focus `bg-accent text-accent-foreground`.
- Keyboard behavior (arrows, Enter/Space, Esc, typeahead) comes from the primitive. Do not reimplement.

### 6.6 Table
Wrapper allows overflow; `w-full text-sm`. Header row `border-b`; header cell `h-10 px-2 text-left align-middle font-medium text-muted-foreground`. Body row `border-b transition-colors hover:bg-muted/50 data-[state=selected]:bg-muted`. Cell `p-2 align-middle`. Caption `mt-4 text-sm text-muted-foreground`.

### 6.7 Badge
`inline-flex w-fit shrink-0 items-center justify-center gap-1 overflow-hidden rounded-md border px-2 py-0.5 text-xs font-medium whitespace-nowrap` + focus ring; icons `size-3`.
Variants: default `border-transparent bg-primary text-primary-foreground`; secondary; destructive `bg-destructive text-white`; outline `text-foreground`. Use for status/counts/tags, 1-2 words.

### 6.8 Alert
`relative w-full rounded-lg border px-4 py-3 text-sm` with grid for an optional leading icon; title `font-medium`, description `text-muted-foreground text-sm`. Variants: default; destructive (`text-destructive border-destructive/50`). Use Alert for callouts, not custom divs.

### 6.9 Toast (Sonner)
One `<Toaster />` at app root. Surface `bg-popover text-popover-foreground border`. Types: default, success, info, warning, error, loading. Keep messages short; optional action (Undo). Position bottom-right.

### 6.10 Skeleton
`bg-accent animate-pulse rounded-md`; shape per piece (`rounded-full` avatars, `h-4 w-[250px]` lines, `size-12` avatars). Mirror the real layout to avoid shift. Skeletons for shaped content; spinner for short shapeless waits.

---

## 7. Interaction & Motion

- Transitions: animate color and box-shadow on controls (`transition-[color,box-shadow]`), 150-200ms, `ease-out`. Rationale: feedback should feel instant, never theatrical.
- Enter/exit (dialogs, menus, popovers): `animate-in`/`animate-out` vocabulary (`fade-in`, `zoom-in-95`, `slide-in-from-*`), enter ~200ms, exit ~150ms, driven by `data-[state=open]`/`data-[state=closed]`. Per the shadcn/ui changelog (March 19, 2025), tailwindcss-animate is deprecated in favor of tw-animate-css (`@import "tw-animate-css";` in Tailwind v4).
- Hover feedback = small background/opacity shift, never size jumps or large scale/translate.
- Focus rings are the primary interaction feedback. Never remove them; use `focus-visible` (not `focus`) so rings show for keyboard, not mouse.

Reduced motion (required, WCAG 2.3.3): wrap non-essential animation in `motion-safe:` or disable via `motion-reduce:animate-none motion-reduce:transition-none`. Plain CSS:
```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```
Status animations (spinners) need a text fallback.

---

## 8. Responsive Behavior

- Breakpoints (Tailwind defaults): sm 640, md 768, lg 1024, xl 1280, 2xl 1536. Design mobile-first; add complexity upward.
- Standard collapses: multi-column grids go single-column below md (`grid-cols-1 md:grid-cols-2 lg:grid-cols-3`); sidebars become a Sheet/drawer below lg; Dialogs may become full-width Sheets/Drawers on mobile; tables scroll horizontally in their wrapper rather than reflowing.
- Text inputs use `text-base` on mobile and `md:text-sm` on desktop (prevents iOS zoom-on-focus).
- Touch targets: minimum 44x44 CSS px on mobile. This matches Apple HIG (44x44 pt) and WCAG 2.2 SC 2.5.5 Target Size (Enhanced, AAA); the WCAG 2.2 AA floor (SC 2.5.8) is only 24x24 px and Material recommends 48x48 dp, but 44px is this system's floor. A visually small control may use padding or a pseudo-element to reach it.
- Type scales down gracefully: h1 `text-4xl lg:text-5xl`; never let headings exceed ~90% of viewport width without wrapping (`text-balance`).
- Spacing tightens one step on mobile (e.g. `p-4 md:p-6`, `gap-4 md:gap-6`); never below 16px page gutter.

---

## 9. Accessibility (non-negotiable)

- Semantic HTML first (`<button>`, `<a>`, `<label>`, `<nav>`, `<table>`); add ARIA roles only when replacing a native element.
- Keyboard: every interactive element reachable and operable (Tab/Shift+Tab/Enter/Space/Esc/arrows). Keep behavior on the correct element via the `asChild`/render-slot pattern; don't wrap triggers in divs that strip roles.
- Focus: visible indicator on all focusables; trap focus in modals; return focus to trigger on close.
- Labels: every input has a label; icon-only buttons need `aria-label`; Dialog/Sheet/Drawer require a Title.
- Contrast: WCAG 2 SC 1.4.3 Level AA - at least 4.5:1 for normal text, 3:1 for large text (18pt/24px, or 14pt/18.5px bold), 3:1 for non-text UI (borders, focus rings, icons). Verify `muted-foreground` meets 4.5:1 on its surface for any must-read text; darken the token if not.
- Never rely on color alone; pair with text or icon. Images have `alt`; decorative images use empty `alt`.

---

## 10. Dark Mode

- Class-based: toggle `.dark` on `<html>`. Tokens are redefined under `.dark`; components need zero per-element overrides.
- Never write manual `dark:` color overrides like `bg-white dark:bg-gray-950`. Use semantic tokens (`bg-background text-foreground`) and both modes work automatically.
- Offer system/auto plus explicit light/dark; persist the choice. Custom tokens must define both `:root` and `.dark` values.

---

## 11. Do's and Don'ts

Do:
- Use semantic tokens for every color: `bg-primary`, `text-muted-foreground`, `border-border`, `bg-card`.
- Use built-in variants first (`variant="outline"`, `size="sm"`), then layout utilities, then CSS variables; edit component source only as a last resort.
- Use `className`/inline styles for layout only (`max-w-md`, `mx-auto`, `mt-4`, grid/flex), not to override component colors or typography.
- Use `gap-*` between children; `size-*` when width equals height.
- Compose full anatomies (full Card, label + field, Dialog with Title).
- Keep the palette restrained; let one accent and destructive carry the weight.
- Honor reduced motion, keyboard, and focus behavior.

Don't:
- Don't use raw Tailwind color scales for UI or status (`bg-blue-500`, `text-green-600`). Use tokens/variants or add a semantic variable (Section 2.3).
- Don't add manual `z-index` on overlay components.
- Don't remove focus outlines or replace `focus-visible` with `focus`.
- Don't use placeholder text as the only label.
- Don't hand-roll accessible widgets (dialogs, menus, comboboxes) when a primitive exists.
- Don't use large hover scale/translate, colored glows, or heavy shadows.
- Don't hardcode light-only colors or off-scale spacing/radius values.

---

## 12. Agent Prompt Guide

Reusable instructions to embed when generating or reviewing UI against this file.

Generation preamble (prepend to any UI task):
"Follow DESIGN.md strictly: shadcn/ui new-york conventions, semantic CSS-variable tokens only (no raw color utilities), 14px UI text, h-9 controls, rounded-md controls / rounded-xl cards, shadow-xs/sm resting elevation, focus-visible rings, gap-based spacing on the 4px scale, mobile-first responsive per Section 8, and full dark-mode support via tokens (no dark: color overrides)."

Artifact/prototype preamble (single-file HTML) - pair it with the artifact rules in Section 13:
"Inline the :root and .dark token block from DESIGN.md Section 2.2 in a style tag, set body to var(--background)/var(--foreground) with the system font stack (`-apple-system, BlinkMacSystemFont, ui-sans-serif, system-ui, sans-serif` - San Francisco on Apple devices), and build controls per Sections 5-6. Never load or embed webfonts. Keep it monochrome and restrained."

Self-review checklist (run before finishing any UI output):
1. Any hex/rgb/raw Tailwind color that isn't a token? Replace it.
2. Any text below 4.5:1 contrast, or focus ring below 3:1? Fix the token usage.
3. Any focusable element without a visible focus-visible ring? Add the universal ring.
4. Any input without a label, icon button without aria-label, or dialog without a title? Add it.
5. Any off-scale spacing, radius, or shadow? Snap to the scales in Sections 4-5.
6. Does it collapse correctly at sm/md/lg, with 44px touch targets?
7. Does toggling .dark produce a correct theme with zero extra overrides?

Escalation rule: if a request conflicts with this file (e.g. "make the button bright green"), comply with the user but implement it as a semantic token (a `--success`-style pair defined for both modes), and note the deviation.

---

## 13. Artifact pages

These apply on top of everything above, and override the defaults above where they conflict.

- **Fonts:** always the system font stack or San Francisco - `-apple-system, BlinkMacSystemFont, ui-sans-serif, system-ui, sans-serif`, mono `ui-monospace, 'SF Mono', Menlo, monospace`. Never embed or inline webfonts in an artifact, including as data URIs.
- **Progress-tracking artifacts** (task boards, project status, migration/rollout trackers, todo dashboards) are ALWAYS kanban-styled: columns for stages, cards for items, a card count per column.
- **Progress-tracking artifacts are ALWAYS full width.** No centered `max-w-*` container: columns span the viewport with page-gutter padding only, and the column row scrolls horizontally inside its own container when columns overflow.
- **Board styling comes from the tokens above:** column surface `muted`, cards `card` plus a hairline border and `shadow-xs`, stage labels as uppercase muted text with counts, and status accents via semantic tokens only.

---

## Notes and caveats

- Class strings reflect the current new-york + Tailwind v4 registry (verified 2026). Older tutorials show Tailwind v3 values (`h-10` buttons/inputs, `ring-2 ring-offset-2`, `rounded-lg` cards); do not use those. If your installed components differ, your local component source is the source of truth; this file's tokens and principles remain the guide.
- The newest Base UI card variant replaces hardcoded `py-6/gap-6/px-6` with a `--card-spacing` variable (default `--spacing(4)`) and uses `ring-1 ring-foreground/10` instead of `border shadow-sm`. Both forms are current; Section 6.3 gives the widely installed Radix new-york version.
- The single most important rule when editing components: change the surface (styles) freely, never the foundation (roles, focus, keyboard wiring).