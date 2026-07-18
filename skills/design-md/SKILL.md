---
name: design-md
description: The user's own design system (DESIGN.md, shadcn/ui rules) for generating UIs. MUST be loaded before writing any frontend or UI code - components, pages, prototypes, dashboards, styling work - and before creating or publishing ANY Artifact page (load it alongside artifact-design; artifact-design's "honor an existing design system" clause refers to this skill). Covers design tokens, OKLCH theme values, typography, spacing/radius/elevation scales, component recipes, motion, responsive behavior, accessibility, and dark mode. Generation defaults only; for auditing or extending a project's existing design system, use the design-system skill instead.
---

Read `DESIGN.md` in this skill's folder before writing or reviewing any UI code, and derive every color, typography, spacing, and component decision from its tokens and recipes.

Rules of precedence:
1. The user's explicit visual direction always wins.
2. A design system already present in the project (a project-local `DESIGN.md`, theme/token files, existing component styles) wins over this file.
3. Otherwise, apply `DESIGN.md` fully - tokens, type scale, control dimensions, component anatomy, motion, responsive behavior, and accessibility requirements are all normative, including for quick artifacts and prototypes (see its Agent Prompt Guide, Section 12, for the generation and artifact preambles and the self-review checklist).

This applies to frontend engineering work (components, pages, styling, reviews) and to artifact/prototype generation alike.
