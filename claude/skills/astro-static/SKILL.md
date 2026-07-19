---
name: Astro for Static & Content Sites
description: Use when building landing pages, company profiles, blogs, or content-first static sites — Astro islands architecture, zero-JS default, React integration
globs: ["**/*.astro", "**/astro.config.*", "**/src/content/**", "**/src/pages/**/*.astro", "**/src/layouts/**"]
---

# Astro for Static & Content Sites

## When to Use Astro vs React SPA

| Criterion | Use Astro | Use React SPA (Vite + TanStack Router) |
|---|---|---|
| Content-driven (blog, docs, marketing) | Yes | No |
| Landing pages, company profiles | Yes | No |
| SEO critical | Yes | Possible but harder |
| Complex interactivity (dashboards, forms) | No | Yes |
| Real-time features (chat, notifications) | No | Yes |
| Auth-gated pages with complex state | No | Yes |
| Static content + few interactive widgets | Yes (islands) | Overkill |

**Rule**: Astro for content sites, React SPA for applications. Never use Astro for dashboards or complex CRUD apps.

## Astro 6 Key Features (2026)

- **Islands Architecture**: interactive components hydrate independently — rest is static HTML
- **Zero JS by default**: ships pure HTML/CSS, JavaScript only where you opt-in
- **Content Collections**: type-safe markdown/MDX with Zod schema validation
- **Live Content Collections** (v6): fetch from CMS at request time, no rebuilds
- **View Transitions**: native page transitions without SPA
- **Server Islands** (v6): defer slow components to load after page shell
- **React integration**: `client:load`, `client:visible`, `client:idle` hydration directives
- **Cloudflare Workers runtime** (v6): dev server matches production runtime

## Project Structure
```
src/
  pages/          # File-based routing (*.astro, *.md, *.mdx)
  layouts/        # Page layouts (BaseLayout.astro, BlogLayout.astro)
  components/     # Astro + React/Svelte/Vue components
    react/        # React components (hydrated islands)
  content/        # Content collections (blog posts, projects)
    config.ts     # Collection schemas (Zod)
  styles/         # Global CSS
  assets/         # Images (optimized by Astro)
public/           # Static assets (favicon, robots.txt)
astro.config.mjs  # Astro configuration
```

## React Integration (Islands)
```astro
---
// src/pages/index.astro
import BaseLayout from '../layouts/BaseLayout.astro';
import Hero from '../components/Hero.astro';        // Static (no JS)
import ContactForm from '../components/react/ContactForm.tsx'; // Interactive
---

<BaseLayout title="Company Name">
  <Hero />                                          <!-- Pure HTML -->
  <ContactForm client:visible />                    <!-- Hydrates when scrolled into view -->
</BaseLayout>
```

### Hydration Directives
- `client:load` — hydrate immediately on page load (above-fold interactive)
- `client:visible` — hydrate when scrolled into viewport (lazy)
- `client:idle` — hydrate when browser is idle (low priority)
- `client:media="(max-width: 768px)"` — hydrate only on matching media query
- No directive = static HTML only (zero JS shipped)

## Content Collections (Type-Safe)
```typescript
// src/content/config.ts
import { defineCollection, z } from 'astro:content';

const blog = defineCollection({
  type: 'content',  // markdown/MDX
  schema: z.object({
    title: z.string(),
    description: z.string(),
    pubDate: z.coerce.date(),
    author: z.string(),
    tags: z.array(z.string()).default([]),
    draft: z.boolean().default(false),
    heroImage: z.string().optional(),
  }),
});

export const collections = { blog };
```

## Performance Principles for Astro

1. **Default to zero JS** — only add `client:*` directives where interaction is essential
2. **Use `client:visible`** for below-fold components (scroll-triggered hydration)
3. **Optimize images** — use `<Image />` component from `astro:assets` (automatic WebP, sizing)
4. **Prefetch links** — `<a href="/about" data-astro-prefetch>` for instant navigation
5. **View Transitions** — `<ViewTransitions />` in layout for SPA-like feel without JS framework
6. **Static by default** — pre-render at build time, use SSR only for dynamic pages
7. **Font optimization** — self-host fonts, use `font-display: swap`, preload critical fonts

## SEO & Meta
```astro
---
// src/layouts/BaseLayout.astro
const { title, description, image } = Astro.props;
const canonicalURL = new URL(Astro.url.pathname, Astro.site);
---
<html lang="id">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{title}</title>
  <meta name="description" content={description} />
  <link rel="canonical" href={canonicalURL} />
  <meta property="og:title" content={title} />
  <meta property="og:description" content={description} />
  <meta property="og:image" content={image} />
  <meta property="og:type" content="website" />
</head>
<body><slot /></body>
</html>
```

## Tailwind CSS v4 Integration
```javascript
// astro.config.mjs
import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  integrations: [react()],
  vite: { plugins: [tailwindcss()] },
});
```
