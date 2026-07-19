---
name: UI/UX Design Laws & Principles
description: Complete 30 UX laws from lawsofux.com + Gestalt, cognitive, behavioral design, information architecture, accessibility, motion design
globs: ["**/*.tsx", "**/*.jsx", "**/*.css", "**/*.html", "**/*.astro", "**/components/**", "**/pages/**", "**/routes/**", "**/app.css", "**/globals.css"]
---

# UI/UX Design Laws & Principles

Source: lawsofux.com (Jon Yablonski), "Laws of UX" book, Nielsen Norman Group, Baymard Institute

## Heuristic Laws

### Jakob's Law
"Users spend most time on OTHER sites. They prefer your site to work the same way."
- Use familiar patterns: sidebar nav, card grids, modal confirmations
- Don't reinvent navigation, form patterns, or checkout flows

### Fitts's Law
"Time to acquire a target is f(distance / size). Larger + closer = faster to click."
- Primary CTAs: large, prominent, in thumb zone on mobile (bottom 1/3)
- Destructive buttons (Delete): smaller, farther from primary action
- Touch targets minimum 44x44px. Edge/corner = infinite target size
- Group related actions close together

### Hick's Law (Hick-Hyman)
"Decision time increases logarithmically with number of choices."
- Max 5-7 visible options at once, rest in dropdown/pagination
- Multi-step wizards over one giant form
- Highlight recommended option to reduce decision paralysis
- Progressive disclosure: show what's needed now, hide the rest

### Miller's Law
"Working memory holds 7±2 items."
- Chunk: phone numbers (3-4-4), credit cards (4-4-4-4)
- Group nav into 5-7 sections max
- Limit visible tags/categories per group

### Doherty Threshold
"Productivity soars when system response < 400ms."
- Optimistic UI updates for common actions
- Skeleton loaders appear instantly (perceived performance)
- Stream AI responses (show tokens as they arrive)
- >1s: progress indicator. >10s: show percentage

### Postel's Law (Robustness Principle)
"Be conservative in what you send, liberal in what you accept."
- Accept flexible input ("+62 812" and "0812"), emit strict output (always "+62812...")
- Tolerate format variations in forms

### Tesler's Law (Conservation of Complexity)
"Every system has inherent complexity that cannot be removed — only moved."
- System absorbs complexity, not the user
- AI calculates team size automatically, user just confirms
- Smart defaults eliminate unnecessary decisions

### Occam's Razor
"Among competing solutions, the one with fewest assumptions is best."
- Simplest UI that works is the best UI
- Don't add options/config for rare use cases
- Default values should be optimal for 80% of users

### Pareto Principle (80/20)
"80% of effects come from 20% of causes."
- 80% of users use 20% of features — prioritize those
- Surface frequent features, hide rare ones in settings
- Optimize the critical path first

### Parkinson's Law
"Work expands to fill the time available."
- Countdowns and deadlines in UI drive completion
- Time-limited offers create urgency
- Step indicators show how close to done

## Gestalt Principles

### Law of Proximity
"Elements near each other are perceived as a group."
- Related form fields: group in sections with clear spacing
- Card internals close together, cards separated by gap

### Law of Similarity
"Similar elements are perceived as belonging together."
- Same function = same style everywhere
- Differentiate categories through color, shape, or icon

### Law of Prägnanz (Simplicity)
"People perceive and interpret ambiguous images in the simplest form possible."
- Clean, simple shapes for icons and UI elements
- Reduce visual noise — every element must earn its place
- Prefer familiar geometric shapes over complex illustrations

### Law of Common Region
"Elements within a boundary are perceived as a group."
- Cards, bordered sections, background color blocks
- Form fieldsets with borders group related inputs

### Law of Uniform Connectedness
"Connected elements are perceived as a single unit."
- Lines connecting nodes in dependency graphs
- Breadcrumb separators connect navigation items
- Stepper components with connecting lines

### Closure (implicit)
"Mind completes incomplete shapes."
- Progress bars leverage this — users want to close the gap
- Partially visible cards at edge suggest scrollable content

## Cognitive Laws

### Cognitive Load Theory (Sweller)
Three types:
- **Intrinsic**: inherent complexity (simplify the task itself)
- **Extraneous**: poor design adding unnecessary processing (ELIMINATE)
- **Germane**: effort forming mental models (FACILITATE)
- Signposting: breadcrumbs, step indicators, section headers

### Cognitive Bias
"Systematic patterns of deviation from rationality in judgment."
- Anchoring: first number seen influences all subsequent estimates
- Confirmation bias: users seek info confirming existing beliefs
- Framing effect: same info presented differently changes decisions
- Design for bias awareness — don't exploit, but account for it

### Mental Model
"What users THINK about how a system works."
- Match UI to user's existing mental model (not developer's model)
- Use real-world metaphors (shopping cart, folder, trash)
- Progressive disclosure aligns with how users build mental models

### Selective Attention
"People focus on relevant stimuli while ignoring irrelevant ones."
- Banner blindness: users ignore ad-like elements — don't style CTAs like ads
- Important info inline in content flow, not floating banners
- Visual hierarchy guides attention to what matters

### Working Memory
"Temporary storage for information being actively processed."
- Don't require users to remember info between pages
- Show context: current step, previous selections, summary
- Autocomplete and suggestions reduce memory demands

### Flow (Csikszentmihalyi)
"Optimal state of engagement when challenge matches skill level."
- Progressive difficulty: easy onboarding → advanced features
- Clear goals + immediate feedback + appropriate challenge
- Remove interruptions during focused tasks (no popups mid-form)

### Chunking
"Breaking information into smaller, manageable units."
- Phone numbers, credit cards, dates, long IDs
- Step-by-step wizards chunk a complex process
- Paragraph breaks, headings, bullet points chunk text

## Behavioral & Motivational Laws

### Von Restorff Effect (Isolation Effect)
"Distinctive items are remembered better."
- CTA buttons: contrasting color. "New"/"Recommended" badges
- Highlight current step in wizard

### Serial Position Effect
"People remember first (primacy) and last (recency) items best."
- Key info at beginning and end of lists
- Most important nav items first and last

### Peak-End Rule
"People judge experiences based on peak moment and the end."
- Key moments (BRD received, project completed): celebration UI
- End of flows: smooth, satisfying confirmation
- Recover gracefully from errors (helpful, not just "Something went wrong")

### Zeigarnik Effect
"Incomplete tasks are remembered better than completed ones."
- Progress bars drive completion ("Profile 70% complete")
- Show incomplete milestones prominently

### Goal-Gradient Effect
"Effort increases as people approach a goal."
- Progress bars accelerate behavior near completion
- "2 more steps" more motivating than "Step 3 of 5"
- Pre-fill progress (start at 10% with account creation)

### Choice Overload (Paradox of Choice)
"More options lead to less satisfaction and decision paralysis."
- Default selections reduce choice burden
- "Recommended" tags reduce decision anxiety
- AI-powered defaults: pre-select optimal option

### Paradox of the Active User
"Users prefer to start using a system immediately rather than reading instructions."
- Users skip tutorials and manuals — design for exploration
- Make common actions discoverable through the UI itself
- Inline hints > separate help pages
- Error recovery > error prevention documentation

### Endowment Effect
"People overvalue things they own or have invested effort in."
- Auto-save everything — saved drafts feel valuable
- "Your BRD" / "Your project" — possessive language increases commitment

### Loss Aversion (Kahneman & Tversky)
"Losses feel ~2x more impactful than equivalent gains."
- "Don't lose your escrow protection" > "Get escrow protection"
- Unsaved changes warnings drive saves
- Free trial ending: "You'll lose access to..." drives conversion

### Anchoring Effect
"First number seen heavily influences subsequent judgments."
- Show higher price first, then actual (discount perception)
- AI-suggested range before user inputs budget

## Layout & Visual Hierarchy

### F-Pattern (text-heavy pages)
- Key info top-left, headings carry most weight, left-align important info

### Z-Pattern (action-oriented pages)
- Landing pages: logo (top-left) → CTA (top-right) → content (bottom-left) → CTA (bottom-right)

### Horror Vacui vs Whitespace
- Whitespace improves comprehension 20%. Let content breathe
- Premium feel: more whitespace. Budget feel: dense

## Accessibility as UX Law

### Inclusive Design (Microsoft)
1. Recognize exclusion — disability is a mismatch between person and environment
2. Solve for one, extend to many — captions help deaf users AND people in noisy rooms

### WCAG POUR Principles
- **Perceivable**: alt text, contrast 4.5:1, captions
- **Operable**: keyboard nav, no traps, focus indicators
- **Understandable**: predictable UI, clear errors, consistent nav
- **Robust**: works across browsers, assistive tech, devices

### Motion Design
- Meaningful, functional, respect `prefers-reduced-motion`
- 100-300ms for UI transitions, 300-500ms for page transitions
- ease-out for entrances, ease-in for exits
