---
name: Tailwind UI Patterns
description: Tailwind CSS v4, shadcn/ui, React component patterns, accessibility
globs: ["**/*.tsx", "**/*.jsx", "**/tailwind.config.*", "**/app.css", "**/globals.css", "**/components/ui/**"]
---

# Tailwind UI Patterns

## Tailwind CSS v4
- Import via `@import "tailwindcss"` (not @tailwind directives)
- Design tokens via `@theme { }` block in CSS
- CSS variables for colors: `--color-primary-500: #1d4a54`
- Use @tailwindcss/vite plugin (not postcss)

## shadcn/ui
- Components in `components/ui/` directory
- Built on Radix UI primitives (accessible by default)
- Use `cn()` utility for conditional classes
- Customize via CSS variables, not component props

## Component Patterns
- Four-state UI: empty, loading (skeleton), error (retry), partial
- Skeleton loaders, not spinners on blank pages
- Error boundaries per section, not whole page
- Responsive: mobile-first, test at sm/md/lg/xl breakpoints

## Accessibility (WCAG AA)
- Contrast ratio 4.5:1 minimum for text
- Focus indicators: focus-visible:ring-2
- Keyboard navigation: Tab, Enter, Space, Escape
- aria-live="polite" for dynamic content
- Touch targets minimum 44x44px on mobile
- prefers-reduced-motion: disable animations
