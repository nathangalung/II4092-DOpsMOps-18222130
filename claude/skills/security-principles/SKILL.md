---
name: Security Engineering Principles
description: Use when touching auth, user input, secrets, or dependencies, and when reviewing for vulnerabilities — OWASP 2025 prevention, defense in depth, threat modeling
globs: ["**/*.ts", "**/*.py", "**/*.go", "**/*.rs", "**/*.java", "**/auth/**", "**/security/**", "**/middleware/**", "**/.env*", "**/Dockerfile*"]
---

# Security Engineering Principles & Laws

## Core Security Principles

### CIA Triad
- **Confidentiality**: data accessible only to authorized parties (encryption, access control)
- **Integrity**: data not tampered with (checksums, digital signatures, audit logs)
- **Availability**: system accessible when needed (redundancy, DDoS protection, backups)

### Principle of Least Privilege (PoLP)
"Grant minimum access required, revoke when no longer needed."
- Database: read-only accounts for reporting, write access only where needed
- API: scoped tokens (read vs write vs admin)
- Container: run as non-root, drop capabilities
- File system: restrict access to what the process needs

### Defense in Depth
"Multiple layers of security — if one fails, others still protect."
Layer 1: Network (firewall, CORS, rate limiting)
Layer 2: Authentication (session validation, OAuth)
Layer 3: Authorization (RBAC, resource ownership)
Layer 4: Input validation (Zod schemas, sanitization)
Layer 5: Business logic (state machine guards, invariant checks)
Layer 6: Data (encryption at rest, parameterized queries)
Layer 7: Output (encoding, CSP headers)

### Zero Trust Architecture
"Never trust, always verify — even inside the network."
- Authenticate every service-to-service call (X-Service-Auth JWT)
- No implicit trust based on network location
- Verify identity + authorization on every request
- Encrypt all traffic (TLS everywhere, even internal)

### Kerchkhoff's Principle
"A system should be secure even if everything except the key is public."
- Security through obscurity is NOT security
- Assume attackers know your architecture, algorithms, source code
- Security rests on keys, credentials, and access controls — not hidden endpoints

### Fail Secure (Not Fail Open)
"When a security mechanism fails, deny access by default."
- Auth service down → deny all requests (don't bypass auth)
- Rate limiter down → use stricter local limits (don't remove limits)
- Permission check fails → deny access (don't grant access)

## OWASP Top 10 (2025) — Prevention Patterns

Source: owasp.org/Top10/2025 — based on 175K+ CVEs and global practitioner survey

### A01:2025 Broken Access Control
- Deny by default: explicit allow, not explicit deny
- Validate resource ownership: `WHERE user_id = currentUser.id`
- RBAC checks in middleware, not scattered in handlers
- Token scope validation: check token has required permissions

### A02:2025 Security Misconfiguration (was #5 in 2021, now #2)
- Config validation at startup (Zod schema for env vars — fail fast)
- Disable debug endpoints in production
- Security headers: CSP, X-Frame-Options, X-Content-Type-Options, HSTS
- Remove default accounts, change default passwords

### A03:2025 Software Supply Chain Failures (NEW — absorbs 2021 A06 'Vulnerable Components')
- Generate and maintain SBOM (Software Bill of Materials) for all software
- Automated dependency scanning in CI (Trivy + Grype); Dependabot/Renovate for security updates
- Use OWASP Dependency-Track for continuous dependency monitoring
- Pin dependency versions, verify checksums, use lockfiles
- Staged rollouts: never deploy updates to all systems simultaneously
- Only obtain components from official sources over secure links
- Monitor OSV (Open Source Vulnerabilities) database continuously

### A04:2025 Cryptographic Failures (was #2 in 2021, now #4)
- Passwords: Argon2id (via Better Auth, built-in)
- Secrets: environment variables, never in code or logs
- Transport: TLS 1.2+ everywhere
- Storage: encrypt PII at rest, hash irreversible data

### A05:2025 Injection (was #3 in 2021, now #5)
- SQL: parameterized queries (Drizzle ORM, automatic)
- NoSQL: schema validation before query construction
- OS Command: never construct shell commands from user input
- LDAP/XPath: parameterized queries

### A06:2025 Insecure Design (was #4 in 2021)
- Threat modeling during design, not after implementation
- Abuse case analysis: how would an attacker use each feature?
- Rate limiting on all sensitive operations (login, payment, AI)
- Security unit tests: test auth bypass, injection, privilege escalation

### A07:2025 Authentication Failures (2025 name; was 'Identification and Authentication')
- Multi-factor authentication for admin accounts
- Account lockout after failed attempts (Better Auth built-in)
- Session timeout and rotation after privilege escalation
- Password complexity requirements (length > 12, complexity optional)

### A08:2025 Software and Data Integrity Failures
- Verify webhook signatures from payment/external providers (HMAC-SHA512, provider callback tokens)
- Validate JWT signatures (don't trust claims without verification)
- Code signing for deployment artifacts
- SBOM attestation for container images

### A09:2025 Logging & Alerting Failures (was 'Security Logging and Monitoring')
- Log all authentication events (success + failure)
- Log all authorization failures
- Log all input validation failures
- Never log secrets, passwords, tokens, PII
- Alert on anomalies (spike in auth failures = brute force attempt)

### A10:2025 Mishandling of Exceptional Conditions (NEW)
"Secure error handling and resilience prevent information leakage and system compromise."
- Never expose stack traces, internal paths, or system info in error responses
- Catch and handle ALL exceptions — unhandled exceptions = undefined behavior = vulnerability
- Fail closed: on error, deny access, don't default to permissive
- Log error details internally (Pino structured JSON), return generic message to user
- Test error paths explicitly — fuzzing, invalid input, resource exhaustion

### A-legacy: Server-Side Request Forgery (SSRF)
- Whitelist allowed external URLs
- Block requests to internal IP ranges (10.x, 172.16.x, 192.168.x, 127.x)
- Don't follow redirects from user-supplied URLs
- Validate URL scheme (https only, not file://, gopher://)

## Secure Coding Laws

### Input Validation Rules
"All input is hostile until validated."
- Validate type, length, range, format at API boundary
- Whitelist approach: define what IS allowed (not what isn't)
- Validate on server side (client validation is UX, not security)
- Sanitize for output context (SQL, HTML, URL, shell — each different)

### Output Encoding Rules
- HTML context: escape < > & " ' (React does this automatically)
- URL context: encodeURIComponent()
- SQL context: parameterized queries (never string concatenation)
- Shell context: avoid entirely, use APIs instead of exec()
- CSS context: escape special characters, avoid user-controlled CSS

### File Upload Security
- Validate MIME type via magic bytes (not just extension)
- Generate random filenames (UUID, prevent path traversal)
- Store outside webroot (S3/R2, not local filesystem)
- Scan for malware before processing (ClamAV for high-risk)
- Size limits enforced (5MB CV, 10MB attachments)
- Don't serve user-uploaded files from your domain (use CDN/separate domain)

### Secret Management
- Environment variables for runtime secrets
- Secret manager for rotation (Infisical, Vault)
- Never commit secrets (use .gitignore, pre-commit hooks)
- Rotate secrets on suspected compromise
- Different secrets per environment (dev ≠ staging ≠ prod)

## Threat Modeling (STRIDE)

### STRIDE Categories
- **S**poofing: pretending to be another user/service → authentication
- **T**ampering: modifying data in transit/at rest → integrity checks
- **R**epudiation: denying actions → audit logging
- **I**nformation Disclosure: exposing data → encryption, access control
- **D**enial of Service: making system unavailable → rate limiting, scaling
- **E**levation of Privilege: gaining unauthorized access → authorization, RBAC

### Threat Modeling Process
1. **Identify assets**: what are you protecting? (user data, payments, secrets)
2. **Identify threats**: who would attack? how? (STRIDE per component)
3. **Identify vulnerabilities**: where are the weaknesses?
4. **Rate risk**: likelihood × impact = priority
5. **Mitigate**: implement controls for highest-risk threats first

## Supply Chain Security

### Dependency Security
- Lock all dependency versions (bun.lock, uv.lock, go.sum, Cargo.lock)
- Verify checksums on install
- Minimal dependencies: fewer deps = smaller attack surface
- Review new dependencies before adding (check maintainers, license, vulnerabilities)
- Prefer well-maintained packages from known organizations

### Container Security
- Minimal base images (distroless, alpine, slim)
- Multi-stage builds (don't ship build tools in production)
- Non-root user in container
- Read-only filesystem where possible
- Scan images in CI (Trivy: container + dependency + IaC)
- Sign images for supply chain integrity
