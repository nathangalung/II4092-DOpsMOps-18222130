---
name: Frontend Development Principles
description: Use when building or reviewing web UI architecture — Core Web Vitals, rendering strategy, state management, component design, a11y
globs: ["**/*.tsx", "**/*.jsx", "**/*.ts", "**/*.js", "**/*.css", "**/*.html", "**/*.astro", "**/vite.config.*", "**/astro.config.*", "**/tsconfig.json"]
---

# Frontend Development Principles & Laws

Sources: "Refactoring UI" (Wathan/Schoger), web.dev, React docs, Astro docs

## Framework Selection

| Use Case | Framework | Why |
|---|---|---|
| Complex app (dashboard, CRUD, real-time) | React TS + Vite + TanStack Router | Full SPA, rich interactivity |
| Content site (landing, blog, docs) | Astro 6 + React islands | Zero JS default, SEO, fast |
| Marketing / company profile | Astro 6 (static) | Pre-rendered, minimal JS |
| Hybrid (content + some interactivity) | Astro 6 + React islands | Best of both |

**Rule**: Astro for content, React SPA for applications. Never use Astro for dashboards.

## Performance Laws

### RAIL Model (Google)
- **Response**: user input within 100ms
- **Animation**: frame within 10ms (60fps = 16ms budget - 6ms overhead)
- **Idle**: deferred work via requestIdleCallback
- **Load**: interactive within 5s on 3G

### Core Web Vitals
- **LCP** < 2.5s: preload hero, inline critical CSS, SSR above-fold
- **INP** < 200ms: avoid long tasks (>50ms), break up work, web workers
- **CLS** < 0.1: explicit dimensions on images, reserve space for dynamic content

### Critical Rendering Path
DOM → CSSOM → Render Tree → Layout → Paint → Composite
- Minimize critical resources, reduce round trips, minimize bytes

### Cost of JavaScript (Addy Osmani)
"JavaScript is the most expensive resource per byte."
- Code-split aggressively (route + component level)
- Lazy load below-fold. Prefer CSS over JS for animations

## Component Design (Atomic Design — Brad Frost)

1. **Atoms**: button, input, label, icon, badge
2. **Molecules**: search form (input + button), nav item (icon + label)
3. **Organisms**: header (logo + nav + search), project card
4. **Templates**: page-level layout (organisms arranged)
5. **Pages**: templates with real content

### Composition Rules
- Single responsibility per component
- Max 5-7 props before decomposing (Miller's Law for APIs)
- Prefer `children` composition over config props
- Colocation: styles, tests, types next to component

## State Management Hierarchy

| State Type | Tool | Example |
|---|---|---|
| Component local | useState | form input, toggle |
| Server/async | TanStack Query v5 | API data, cache |
| Client global | Zustand v5 | sidebar, theme, modals |
| URL state | TanStack Router params | filters, pagination |
| Form state | React Hook Form + Zod | validation, dirty tracking |

### Key Principles
- **Colocation**: state as close to usage as possible
- **Single source of truth**: TanStack Query cache IS the source for server data
- **Derived state elimination**: don't store what you can compute
- **Optimistic updates**: update UI immediately, reconcile in background

## Rendering Principles

- Keys: stable, unique, from data (NOT index)
- Avoid new objects/arrays in JSX (cause re-renders)
- `React.memo` only when measured as needed
- `useDeferredValue`/`startTransition` for non-urgent updates
- `@tanstack/virtual` for lists >100 items
- Web Workers for CPU-intensive computation

## CSS Architecture

### Tailwind v4
- `@import "tailwindcss"` + `@theme {}` block for design tokens
- `@tailwindcss/vite` plugin (not postcss)
- Utility-first eliminates specificity wars

### Layout Hierarchy
1. Flexbox (1D), 2. Grid (2D), 3. Container queries (parent-responsive), 4. Subgrid (nested alignment)

### Modern CSS Features (2025-2026)
- **Container queries**: `@container (min-width: 400px)` — responsive to parent, not viewport
- **`:has()` selector**: parent selector — `div:has(> img)` styles div containing img
- **View Transitions API**: native page transitions — `document.startViewTransition()`
- **CSS Nesting**: native, no preprocessor — `& .child { }` directly in CSS
- **`color-mix()`**: dynamic color blending — `color-mix(in oklch, var(--primary), white 20%)`
- **Scroll-driven animations**: `animation-timeline: scroll()` — animate on scroll without JS

### Motion Design
- Meaningful + functional, respect `prefers-reduced-motion`
- 100-300ms UI transitions, 300-500ms page transitions
- ease-out entrances, ease-in exits, ease-in-out moves

## Error Handling

### Four States (EVERY data component)
1. **Empty**: illustration + CTA ("Create your first project")
2. **Loading**: skeleton loaders matching content shape
3. **Error**: message + retry button + support link
4. **Success**: render content
Missing any one is a bug

### Error Boundary Strategy
- Page-level: catastrophic → full-page error with retry
- Section-level: isolate → rest of page works
- Component-level: high-risk widgets only

## i18n Principles
- ALL strings through `t()` — zero exceptions
- Keys: descriptive `project.create.submit_button` not `btn1`
- Text expansion 30-50% for translations — don't fix widths
- Logical CSS properties (`margin-inline-start` not `margin-left`) for RTL
- ICU MessageFormat for pluralization

## Accessibility (WCAG AA)
- Contrast 4.5:1 text, 3:1 large text. Focus: `focus-visible:ring-2`
- Keyboard: Tab, Enter, Space, Escape. No traps. Skip-to-content link
- `aria-live="polite"` for dynamic content. Touch targets 44x44px minimum
- `prefers-reduced-motion`: disable non-essential animations
- `prefers-contrast: more`: increase borders and text contrast

## React Performance Specifics (2026)

Source: web.dev Core Web Vitals, Sentry React Performance Guide, Addy Osmani

### INP Optimization (Interaction to Next Paint < 200ms)
- **Long tasks >50ms** are the enemy of INP — break up with `startTransition` or `setTimeout`
- **React.memo**: prevents unnecessary re-renders, reduces interaction handler execution by 30-50ms on complex UIs
- **Event handlers**: keep lightweight. Heavy computation → web worker or deferred
- **Avoid layout thrashing**: don't read DOM after write in same frame (forces synchronous layout)

### Why Tailwind > CSS-in-JS for Performance
- CSS-in-JS (styled-components, Emotion) adds 10-30ms runtime overhead per render for style injection+parsing
- Tailwind/CSS Modules: styles parsed ONCE at page load, zero runtime cost
- For React SPAs, this compounds across hundreds of components

### Bundle Size → LCP Impact
- Every 100KB of JS = ~300ms parse+execute on mid-range mobile
- Code split: route-based (TanStack Router auto) + component-based (React.lazy)
- Tree-shake: named exports enable tree-shaking, default exports don't
- Analyze: `npx vite-bundle-visualizer` to find bloat

### Hydration Performance
- SSR HTML must match client render exactly (no Date.now(), Math.random() in initial render)
- `useEffect` for client-only logic (runs after hydration)
- Astro islands: only hydrate interactive components, rest stays static HTML
