# WorldTides Proxy — Technical Design (WT2 candidate)

Status: **design only** — not implemented or deployed. Prepared during WT1.
Purpose: provide WorldTides predictions to approved beta testers without
distributing the subscription API key, keeping Supabase auth, the SQLite
offline-first cache and the existing tide-reference flow unchanged.

## 1. Overview

```
Bragmat app ──HTTPS──> Supabase Edge Function "worldtides-proxy"
   (user JWT)                │  verifies JWT + beta entitlement
                             │  validates + sanitises parameters
                             │  enforces credit budgets (atomic)
                             └──HTTPS──> www.worldtides.info/api/v3
                                      (key held as Edge secret only)
```

The client never sees the WorldTides key. The response body (the WorldTides
JSON) is returned to the app verbatim so the existing parser, tide-context
builder and `tide_cache` storage work unmodified.

## 2. Authentication and entitlement

- Client calls `supabase.functions.invoke('worldtides-proxy', …)` which
  attaches the user's session JWT automatically.
- Function verifies the JWT with `supabase.auth.getUser(jwt)` — rejects
  anonymous/expired tokens (401).
- Entitlement: reuse the existing beta-entitlement model (the same
  check the app uses for `com.bragmat.app` entitlements — a
  `beta_testers` allowlist table keyed by `auth.users.id`, written by the
  owner only). Revocation = delete the allowlist row; enforcement is
  per-request so revocation takes effect immediately.
- No anonymous access path, no service-role bypass in client code.

## 3. Secrets handling

- `WORLDTIDES_API_KEY` stored via `supabase secrets set` — never in the
  repo, client bundle, logs or responses.
- Function logs contain only user id, rounded request bucket and status —
  never the key, request URL, or response body.
- Error responses to the client are sanitised (`502 tide_upstream` etc.);
  upstream error bodies are mapped, not forwarded (they could echo the key
  in `error`/`message` fields — WorldTides includes the request URL in some
  error responses, so always strip).

## 4. Supported operations and validation

Whitelist, mirroring exactly what `WorldTidesService._fetchTideData` sends:

| Param | Rule |
|---|---|
| `extremes` | required, fixed `''` — the only data type allowed |
| `lat`, `lon` | required, decimal, |lat|≤90, |lon|≤180, sane NT-region sanity bound (reject absurd values) |
| `date` | `YYYY-MM-DD`, within a rolling window (e.g. −5y … +3mo) |
| `days` | int 1–7 (production uses 3) |
| `datum` | fixed `CD` |

Everything else (`heights`, `stations`, `plot`, `key`, …) is rejected — the
function owns the key and never forwards client-supplied auth params.

## 5. Credit budgets (atomic, privacy-preserving)

Table `worldtides_usage` (RLS: no client access; function uses service role
internally — service key stays server-side):

```
user_id uuid, period text (YYYY-MM), count int, updated_at
```

Plus a singleton `worldtides_budget_global(period, count)` row.

Enforcement inside a single Postgres function
(`SECURITY DEFINER`, `FOR UPDATE` row lock or `INSERT … ON CONFLICT …
RETURNING`) so the check-and-increment is atomic:

- per-user cap: e.g. 40 credits/month (≫ any real user; kills runaway loops)
- global cap: e.g. 15,000/month — circuit breaker below the 20,000 plan so
  owner's own usage and headroom survive
- on cap exceeded → `429` + `retry_after` hint; app falls back to cache.

Counters store **no coordinates** — only user id + month + count.
Coordinates exist only inside the transient request.

## 6. Client changes (WT2 scope, not WT1)

- `WorldTidesService._fetchTideData`: if no local key AND Supabase session
  exists AND `CLOUD_BACKUP_AVAILABLE`-style feature flag `WORLDTIDES_PROXY`
  is on → call the Edge Function instead of the vendor URL. Response shape
  is identical, so `_parseTideEvents`, `_parseStationInfo`, context builder
  and `cacheTideData` are untouched.
- `isAvailable()` becomes: local key OR authenticated+entitled session
  (cache the entitlement verdict in memory with short TTL to avoid a
  network check per catch).
- Offline: unreachable function → same "Not recorded" path as today; the
  7-day/2 km `tide_cache` still serves repeat locations.
- iOS and Android use the identical Dart path — no per-platform logic.

## 7. Failure handling

| Case | Behaviour |
|---|---|
| No session / entitlement revoked | `TideFailureReason.apiKeyMissing`-style state; UI explains beta restriction |
| Function down / timeout | soft-fail, cache consulted first anyway (unchanged) |
| WorldTides 401/429 upstream | mapped to `tide_unavailable`; owner alerted via usage table review |
| Budget exhausted | `429` until period rollover; catches still save |

## 8. Required Supabase work (WT2, pending approval)

1. `supabase/functions/worldtides-proxy/` (Deno, ~150 lines).
2. Migration: `beta_testers` allowlist table (or reuse existing entitlement
   store if one exists in the project DB) + `worldtides_usage` counters +
   atomic increment RPC.
3. `supabase secrets set WORLDTIDES_API_KEY=…` (owner-side, never in repo).
4. RLS: deny all client access to usage/allowlist tables.
5. Optional: scheduled job to reset monthly counters (or lazy rollover on
   first request of a new period — simpler).

## 9. Open licensing question

Confirm in writing with WorldTides that serving predictions to external
beta testers via an authenticated proxy under the owner's subscription
qualifies as retrieval "on behalf of end users" (terms dated Oct 2026 read
as permitting it; a short confirmation email is recommended before beta).
