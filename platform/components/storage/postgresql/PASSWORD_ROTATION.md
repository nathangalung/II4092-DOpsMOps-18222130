# PostgreSQL `platform` role — password rotation runbook

Rotate the password of the CNPG **application owner role** `platform` (the role
behind every use-case's `pipeline-secrets.POSTGRES_PASSWORD`). Use this after a
credential leak or on a scheduled rotation.

This is a **live, ordered, breakable** operation. It is intentionally **not**
automated and **not** run by the assistant — execute it yourself, in order,
during a maintenance window.

---

## 1. Source-of-truth chain

The `platform` role password originates at the CNPG-generated app secret and
flows outward. Nothing in git holds the password; rotation mutates the live
chain:

```
CNPG Cluster "postgresql" (storage ns)
  bootstrap.initdb.owner = platform        # role created here, password generated
        │
        ▼
  Secret postgresql-app (storage ns)        # {username, password}  ← AUTHORITATIVE ORIGIN
        │   PushSecret  postgresql-app-to-openbao   (refreshInterval 1h, + reconciles on source change)
        ▼
  OpenBao  secret/platform/postgres/app      # {username, password}
        │   ExternalSecret pipeline-secrets   (refreshInterval 1h, per use-case overlay)
        ▼
  Secret pipeline-secrets (<USE_CASE_NS> ns) # POSTGRES_USERNAME / POSTGRES_PASSWORD
        │   envFrom
        ▼
  Consumers in <USE_CASE_NS>                  # incl. the Debezium connector worker (replication)
```

Key facts (verified against the cluster source and CNPG docs):

- The `platform` role is created by `bootstrap.initdb` in
  `cluster.yaml` and has `REPLICATION` (Debezium uses it). It is **not** in the
  CNPG `managed.roles` block (only `feast` and `spicedb` are), so its password
  is **not** declaratively reconciled — rotation is a manual `ALTER ROLE`. See
  §4 of the appendix for why making it declarative is non-trivial and gated.
- `enableSuperuserAccess: false` — the `postgres` superuser has **no password**.
  You rotate `platform` from inside the primary pod over the local socket, where
  CNPG's generated `pg_hba.conf` allows local auth without a password (see the
  pre-flight check in §3).
- `envFrom` is read **once at pod start**. Updating `pipeline-secrets` does
  **not** reach a running consumer pod — every consumer must be restarted
  (step 5). A live PostgreSQL connection is not dropped by `ALTER ROLE`; only
  *reconnects* use the new password, which is why mid-rotation reconnects fail
  until the restart completes.

---

## 2. Pre-flight

```bash
# Identify the primary pod (role=primary).
kubectl get pods -n storage -l cnpg.io/cluster=postgresql,role=primary

# Identify every consumer of pipeline-secrets in the use-case namespace.
kubectl get deploy,sts,rollout -n <USE_CASE_NS> -o json \
  | grep -l pipeline-secrets   # or inspect envFrom.secretRef.name == pipeline-secrets
```

Generate a strong password and keep it to hand for the steps below
(`NEW_PW=$(openssl rand -base64 32 | tr -d '/+=' | head -c 40)`).

---

## 3. Confirm local auth works (one-time check)

With `enableSuperuserAccess: false` the rotation relies on local-socket auth in
the primary pod. Confirm it before you start:

```bash
PRIMARY=$(kubectl get pods -n storage -l cnpg.io/cluster=postgresql,role=primary -o name)
kubectl exec -n storage "$PRIMARY" -c postgres -- psql -U postgres -d platform -c '\conninfo'
```

- If this prints connection info → local auth works; proceed with `-U postgres`
  in step 1.
- If it is rejected → connect as `platform` itself instead (it has `CREATEROLE`
  and can alter its own password). You will need the *current* password:
  `psql "postgresql://platform:CURRENT_PW@localhost/platform" -c '\conninfo'`.

---

## 4. Procedure (validated, runnable)

Run the steps **in order**. Forcing the two ESO refreshes (instead of waiting up
to 1h each) keeps the consumer-failure window to seconds–minutes.

```bash
PRIMARY=$(kubectl get pods -n storage -l cnpg.io/cluster=postgresql,role=primary -o name)

# (1) Rotate the role password in PostgreSQL.
kubectl exec -n storage "$PRIMARY" -c postgres -- \
  psql -U postgres -d platform -c "ALTER ROLE platform WITH PASSWORD '$NEW_PW';"

# (2) Update the authoritative app secret (this is the PushSecret source).
kubectl patch secret postgresql-app -n storage --type merge \
  -p "{\"data\":{\"password\":\"$(printf '%s' "$NEW_PW" | base64 -w0)\"}}"

# (3) Force the PushSecret to publish postgresql-app → OpenBao now
#     (it also reconciles automatically on the source-secret change; this just
#      removes the up-to-1h fallback wait).
kubectl annotate pushsecret postgresql-app-to-openbao -n storage \
  force-sync="$(date +%s)" --overwrite

# (4) Force the use-case ExternalSecret to re-pull OpenBao → pipeline-secrets now.
kubectl annotate externalsecret pipeline-secrets -n <USE_CASE_NS> \
  force-sync="$(date +%s)" --overwrite

# (5) Restart every consumer so envFrom re-reads the new pipeline-secrets.
#     Include the Debezium/Kafka-Connect worker that holds the replication conn.
kubectl rollout restart deployment -n <USE_CASE_NS> \
  -l 'type!=flink-native-kubernetes'
# Restart the Kafka Connect worker explicitly if it is not a labelled Deployment
# above (it carries the Debezium connector that authenticates as `platform`).
```

---

## 5. Verification

```bash
# pipeline-secrets carries the new password (compare to base64 of NEW_PW).
kubectl get secret pipeline-secrets -n <USE_CASE_NS> \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d; echo

# OpenBao holds the new value (via the platform path).
#   (from an OpenBao-authenticated context)
#   bao kv get secret/platform/postgres/app

# No consumer is CrashLooping / auth-erroring after the restart.
kubectl get pods -n <USE_CASE_NS> -w

# Debezium replication is healthy (connector RUNNING, no auth failure in logs).
kubectl logs -n <USE_CASE_NS> deploy/<kafka-connect-deploy> | grep -i 'password\|auth\|FATAL' | tail
```

Old database connections opened before step 1 keep working until they close;
only reconnects use `$NEW_PW`. Once all consumer pods are `Running` and Debezium
shows no auth errors, rotation is complete.

---

## 6. Failure handling

- **A consumer can't authenticate after restart** → its `pipeline-secrets` is
  stale (step 4 didn't propagate). Re-run step 4, confirm via §5, restart that
  consumer again.
- **OpenBao still shows the old password** → step 3 didn't push. Check the
  `PushSecret` status: `kubectl describe pushsecret postgresql-app-to-openbao -n storage`.
- **Need to abort mid-rotation** → re-run step 1 with the *previous* password to
  restore it in PostgreSQL, then steps 2–5 with the old value. There is no
  snapshot to roll back to; the database password is whatever the last
  `ALTER ROLE` set.
- **Coordinate** with any concurrent storage-disruptive maintenance (e.g. a
  ClickHouse keeper migration) so consumers are not bounced twice.

---

## Appendix — proposed declarative rotation (PROPOSED · UNVALIDATED · GATED)

> Not implemented. Documented so the option (and its hazard) is not lost.
> **Do not apply without resolving the circularity below**, and note that the
> first Argo sync of such a change triggers a live `ALTER ROLE` — i.e. it *is*
> the gated cutover, not a safe no-op.

CNPG `managed.roles[*]` reconciles `ALTER ROLE … WITH PASSWORD` from a
`kubernetes.io/basic-auth` secret whose username equals the role name. Adding
`platform` to `managed.roles` would convert every future rotation from the
manual §4 procedure into "update one secret, CNPG reconciles."

**Why it is not landed — the source-of-truth would have to flip, and it cycles:**

Today `postgresql-app` (CNPG-generated) is the origin and OpenBao is a *sink*
(via the `postgresql-app-to-openbao` PushSecret). A `managed.roles[platform]`
`passwordSecret` must be an *input* to CNPG. Pointing it at an OpenBao-derived
ExternalSecret makes OpenBao the origin — but the existing PushSecret still
pushes `postgresql-app` *into* OpenBao, forming a cycle
(`postgresql-app → OpenBao → managed-role secret → ALTER ROLE → …`).

Landing it safely would require **all** of:

1. Removing/​reversing the `postgresql-app-to-openbao` PushSecret so OpenBao is
   the single origin (not both source and sink).
2. Seeding OpenBao `secret/platform/postgres/app` once with a known value.
3. Adding a basic-auth ExternalSecret (username `platform`) for the
   `passwordSecret`, and adding `platform` to `managed.roles`.
4. Confirming nothing reads `postgresql-app` directly (it becomes vestigial).

Each of steps 1–3 mutates the live credential chain, and step 3's first sync
runs a live `ALTER ROLE`. That is a user-gated cutover, identical in risk
profile to §4 — so the declarative option offers no safety win for a one-off
leak rotation. Revisit it only as a deliberate, separately-planned change to the
credential architecture, not as part of incident rotation.
