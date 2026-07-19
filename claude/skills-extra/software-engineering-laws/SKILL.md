---
name: Software Engineering Laws & Principles
description: 40+ SE laws — Conway's, Brooks's, Hyrum's, Lehman's, Goodhart's, Amdahl's, Chesterton's Fence, Pragmatic Programmer, SOLID, DRY, KISS, YAGNI
globs: ["**"]
---

# Software Engineering Laws & Principles

Sources: "The Pragmatic Programmer" (Hunt/Thomas), "Clean Code" (Martin), "A Philosophy of Software Design" (Ousterhout), "Mythical Man-Month" (Brooks)

## Architecture & Design Laws

### Conway's Law
"Organizations design systems mirroring their communication structure."
- Inverse Conway Maneuver: structure teams to match desired architecture

### Gall's Law
"Complex working systems evolved from simple working systems."
- Never design complex from scratch. Start simple, evolve

### Hyrum's Law
"With enough users, every observable behavior becomes depended upon."
- Any API detail, even undocumented, becomes a contract

### Postel's Law (Robustness)
"Be conservative in what you send, liberal in what you accept."

### Principle of Least Astonishment
"Code should do exactly what its name suggests, nothing more."

### Law of Demeter (Least Knowledge)
"A module should only talk to its immediate friends."
- `order.getCustomer().getAddress().getCity()` → `order.getShippingCity()`

### Separation of Concerns
"Each module addresses a separate concern."

### SOLID Principles
- **S**: Single Responsibility — one reason to change
- **O**: Open/Closed — extend without modifying
- **L**: Liskov Substitution — subtypes substitutable for base
- **I**: Interface Segregation — many specific > one general
- **D**: Dependency Inversion — depend on abstractions

### Depth of Module (Ousterhout — "A Philosophy of Software Design")
"Best modules provide powerful functionality behind simple interfaces."
- Deep module: simple interface, complex implementation (good)
- Shallow module: complex interface, trivial implementation (bad)
- Prefer deep modules — they hide complexity effectively

### Tactical vs Strategic Programming (Ousterhout)
- **Tactical**: get feature working ASAP, accumulate complexity
- **Strategic**: invest 10-20% extra time in good design, pays off exponentially
- "The most important thing is the long-term structure of the system"

## Estimation & Project Laws

### Brooks's Law
"Adding manpower to a late project makes it later."
- Ramp-up time + communication overhead. 9 women ≠ 1 month baby

### Hofstadter's Law
"It always takes longer than expected, even accounting for Hofstadter's Law."

### Parkinson's Law
"Work expands to fill time available."

### Ninety-Ninety Rule (Cargill)
"First 90% takes 90% of time. Remaining 10% takes the other 90%."

### Planning Fallacy (Kahneman)
"People systematically underestimate time for future tasks."
- Use reference class forecasting: how long did similar past tasks take?

## Complexity Laws

### Lehman's Laws of Software Evolution
1. **Continuing Change**: adapt or become unsatisfactory
2. **Increasing Complexity**: complexity grows unless actively reduced
3. **Conservation of Familiarity**: incremental changes must stay within team comfort

### Tesler's Law (Conservation of Complexity)
"Inherent complexity can only be moved, not removed." System absorbs it, not user

### Kernighan's Law
"Debugging is twice as hard as writing. If you write cleverly, you're not smart enough to debug it."

### Knuth's Optimization Principle
"Premature optimization is the root of all evil." Make it work → right → fast

### Accidental vs Essential Complexity (Brooks — "No Silver Bullet")
- **Essential**: inherent in the problem domain (can't be removed)
- **Accidental**: introduced by tools, languages, poor design (CAN be removed)
- Most software complexity is accidental — fight it relentlessly

## Scale & Performance Laws

### Amdahl's Law
"Speedup limited by sequential portion." 10% sequential = max 10x speedup

### Little's Law
"L = λW (items in system = arrival rate × wait time)"
- Reduce queue: lower arrival rate (rate limit) or processing time (optimize)

### CAP Theorem
"Distributed: pick 2 of Consistency, Availability, Partition tolerance." Must handle partitions → choose CP or AP

### Universal Scalability Law (Gunther)
"Throughput degrades due to contention (serialization) and coherency (crosstalk)."
- Adding nodes helps until contention dominates, then throughput decreases
- Minimize shared state between nodes

## Human & Organization Laws

### Goodhart's Law
"When a measure becomes a target, it ceases to be a good measure."
- Target code coverage % → devs write meaningless tests

### Dunning-Kruger Effect
"Most confident? That's when you need a second opinion most."

### Linus's Law
"Given enough eyeballs, all bugs are shallow." Code review exists for this

### Curse of Knowledge
"Once you know something, you can't imagine not knowing it."
- Write docs/comments as if reader has NO context

## Pragmatic Principles

### Boy Scout Rule: "Leave code better than you found it."
### Rule of Three: "Refactor on third occurrence." First: do it. Second: note duplication. Third: extract
### YAGNI: "Don't build until you need it." No speculative features
### KISS: "Simplest working solution is best."
### DRY: "Don't Repeat Yourself." But: wrong abstraction is worse than duplication (Rule of Three)
### Chesterton's Fence: "Don't remove until you understand why it was put there." Check git blame
### Fail Fast: "Validate at boundaries immediately." Don't pass invalid data deeper
### Command-Query Separation: Functions either DO something or ANSWER something, not both
### Principle of Least Privilege: "Grant minimum access required."
### Worse is Better (Gabriel): "Simple, correct, consistent, complete — in that priority order." Ship simple first
### You Build It, You Run It (Amazon): "Developers own production." Ops responsibility = better software

## Additional Laws (from laws-of-software.com, Brainhub 38 Empirical Laws)

### Wirth's Law
"Software gets slower faster than hardware gets faster."
- Feature bloat and abstraction layers consume hardware gains
- Performance budgets exist for a reason — fight bloat

### Law of Leaky Abstractions (Joel Spolsky)
"All non-trivial abstractions, to some degree, are leaky."
- ORMs leak SQL. HTTP leaks TCP. Async leaks threading
- Know what's underneath your abstractions — it WILL matter when debugging

### Shirky Principle
"Institutions will try to preserve the problem to which they are the solution."
- Beware of teams that complicate systems to justify their existence
- Automate yourself out of repetitive work, don't protect it

### Zawinski's Law
"Every program attempts to expand until it can read mail. Those that cannot are replaced by ones that can."
- Feature creep is natural. Fight it with YAGNI and scope discipline

### Norvig's Law
"Any technology that surpasses 50% penetration will never double again."
- Market saturation is real. Plan for maturity, not infinite growth

### Kerchkhoff's Principle
"A cryptographic system should be secure even if everything except the key is public."
- Security through obscurity is not security. Assume attackers know your algorithm

### Gilb's Law
"Anything you need to quantify can be measured in some way superior to not measuring it at all."
- Imperfect metrics > no metrics. Measure what matters, even approximately

### Choose Boring Technology (Dan McKinley)
"Each team gets ~3 innovation tokens. Spend them wisely."
- New tech has unknown failure modes. Known tech has known workarounds
- PostgreSQL, Redis, NATS = boring (proven). Use innovation tokens for actual differentiators

### Atwood's Law
"Any application that CAN be written in JavaScript, WILL eventually be written in JavaScript."
- Observation, not recommendation. Sometimes the right tool is NOT JavaScript
