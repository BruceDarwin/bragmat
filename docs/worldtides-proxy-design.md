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

## 9. Licensing — CONFIRMED (Bryan Aamot, Brainware LLC, Oct 2026)

Written confirmation received: the existing 20,000-credit/month
subscription permits serving Bragmat tide predictions to external beta
testers AND the eventual public release — no separate licence required —
under these conditions, each mapped to the implementation:

| # | Condition | Compliance |
|---|---|---|
| 1 | API key stays on the server | `WORLDTIDES_API_KEY` env secret only; never shipped, logged or returned (handler_test asserts non-leakage). |
| 2 | Requests are for individual users | Every proxied call is bound to the caller's verified `uid`; no batch or anonymous mode exists. |
| 3 | Copyright attribution displayed | WT1: tappable notice on the WorldTides card + full licence text in Settings (clickable copyright link). |
| 4 | Per-user caching indefinite; kept in fishing records | `environmental_conditions` rows persist with the user's catches and travel in that user's own ZIP backups. |
| 5 | Cached predictions NOT shared across users | See §9.1 — verified, no sharing path exists. |
| 6 | No resale as standalone dataset | App provides no export of raw tide datasets; tide fields only ever appear attached to the owner's catch records. |
| 7 | New requests subject to available credits | Per-user (40) and global (15,000) per-cycle atomic budgets; 429 on exhaustion. |
| 8 | No separate licence for public release | Recorded — beta usage and public release are both covered under these same conditions. |

### 9.1 Cache-sharing analysis (condition 5)

Audited every path by which a WorldTides prediction could reach a user
other than the requester:

- **Server side**: the proxy persists nothing — no response cache, no
  request log rows. Each request is fetched fresh for the authenticated
  caller. No sharing path exists by construction.
- **`tide_cache` (SQLite)**: lives inside the app's private storage of
  the requesting user's device install. It is **not** exported by
  `backup_service` (which exports `environmental_conditions` only), so a
  backup restored on another device — or by another account — carries no
  shared cache. Repeat same-user requests hit their own device's cache.
- **`environmental_conditions`**: catch-attached predictions are the
  requesting user's own records (explicitly permitted, condition 4) and
  are bound by schema-v29 ownership/unclaimed-data protection on
  restore — they cannot be claimed by a different account.
- **Cloud Backup** (separate branch, disabled for beta): user-scoped,
  encrypted, owner-only restore — same single-user property.

Conclusion: a prediction fetched under user A's entitlement can only
ever be read by user A. Compliant.

## 10. WT2 — as implemented (this branch)

Files:

- `supabase/functions/worldtides-proxy/index.ts` — entrypoint (`Deno.serve`).
- `supabase/functions/worldtides-proxy/handler.ts` — request logic with
  injectable deps (`ProxyDeps`) so auth/entitlement/quotas/upstream are
  unit-testable without a live project.
- `supabase/functions/worldtides-proxy/handler_test.ts` — 14 Deno tests.
- `supabase/migrations/0003_worldtides_proxy.sql` — counters, config,
  hardened SECURITY DEFINER reserve/release functions, admin-only reads.
- `supabase/tests/worldtides_quota_checks.sql` — rolled-back SQL harness
  (16 checks) for post-deployment verification.
- `lib/services/worldtides_service.dart` — null-key requests route to
  `functions.invoke('worldtides-proxy')`; a stored key keeps the direct
  path. Test seams: `httpGetForTesting`, `proxyFetchForTesting`,
  `proxySessionForTesting`.

Decisions worth noting:

- **Entitlement** is `is_approved_beta()` invoked through the *caller's*
  JWT-scoped client (`userClient.rpc`), not the service role — identical
  to the storage/profile precedent, so revocation is enforced per request.
- **Reservation before upstream call.** `worldtides_reserve_credit` uses
  guarded upserts (`ON CONFLICT … WHERE credits < limit`) evaluated under
  the row lock — concurrent requests serialise on `(user_id, cycle)` and
  `cycle` rows, so a parallel burst cannot overdraw either counter.
- **Indeterminate billing is charged.** Timeouts/network failures keep
  the reservation; only an upstream body explicitly reporting
  `callCount === 0` triggers `worldtides_release_credit`. This is
  deliberately conservative: it can never under-count WorldTides spend.
- **Cycle alignment**: `worldtides_config.cycle_anchor_day` (day-of-month
  of the WorldTides subscription renewal — set post-deploy) drives
  `worldtides_cycle_start()`. Counters key on the cycle start date, so a
  new billing period automatically starts fresh rows; nothing needs a
  scheduled reset job.
- **Compromised-client resistance**: reserve/release execute is granted
  to `service_role` only, usage tables grant clients admin-gated SELECT
  only, and the functions use `SECURITY DEFINER` + `search_path = ''`.
  A tampered client can therefore only talk to the Edge Function, where
  every call is re-authenticated, re-authorised, re-validated and
  re-counted — there is no client-reachable path that mints or skips
  credits. Flooding attempts are bounded by the per-user cap (default
  40/cycle), and overall spend by the global circuit breaker (15,000).
- **Privacy**: the function never writes coordinates anywhere; the only
  persistence is `(user_id, cycle, credits)` plus update timestamps.
- **Failure semantics**: 401 → session; 403 → entitlement; 400 → params;
  429 → budget; 500 → missing secret; 502 → upstream/reservation failure.
  All are mapped in the client to the existing graceful "Not recorded"
  degradation — catch saving is unaffected.

Deployment prerequisites (all owner-side, none performed in WT2):

1. Apply `0003_worldtides_proxy.sql` to `bragmat-dev`.
2. `supabase functions deploy worldtides-proxy`.
3. `supabase secrets set WORLDTIDES_API_KEY=<real key>` — never committed.
4. `update public.worldtides_config set value='<dd>' where
   key='cycle_anchor_day';` to match the subscription renewal day.
5. Run `supabase/tests/worldtides_quota_checks.sql` — expect 16/16 PASS.
