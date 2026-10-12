# Stage 4 — Backend Comparison

Evaluation of backend options for user accounts, cloud backup and
multi-device sync. Supersedes nothing; informs approval of
`stage4-user-accounts-architecture.md`.

Evaluation criteria: migration effort, offline reliability, multi-device
conflicts, media synchronisation, security, ongoing maintenance, cost.

## Context that shapes the comparison

- sqflite schema v28, ~15 relational tables, years of migrations. The data
  layer (queries, stats, aggregations across catches/trips/media) is large
  and works.
- Offline-first usage: the app is used on the water, frequently with no
  connectivity. Local SQLite is the source of truth by design.
- Media is file-based with relative paths and collision-safe naming.
- The hardened restore pipeline is a proven local-first recovery pattern.
- Solo developer, beta-scale user base, Windows + future macOS toolchain.

---

## Option 1 — Supabase Auth + PostgreSQL + SQLite sync (proposed)

Local-first: SQLite stays the source of truth; a `SyncService` replicates
deltas to Postgres. Sync engine can be hand-rolled (push `dirty` rows,
pull by `updated_at` watermark) or via a managed SQLite↔Postgres product
(PowerSync, ElectricSQL) — see below.

| Criterion | Assessment |
|---|---|
| Migration effort | **Low.** Additive schema v29 (uuid/owner_id/timestamps/dirty). No existing query or screen changes. Effort is in the sync engine itself. |
| Offline reliability | **Best possible.** UI never touches the network; sync is opportunistic and idempotent. Supabase SDK session persists across restarts. |
| Multi-device conflicts | We own the policy: last-writer-wins on `updated_at` per row — adequate for single-user/two-device beta; upgrade path exists (field-level, vector clocks) without re-architecting. |
| Media sync | Supabase Storage private bucket, keys = `media/{uid}/{relative_path}`, upload-if-absent — maps 1:1 onto existing media semantics and never-overwrite promotion. |
| Security | RLS `owner_id = auth.uid()` on every table + storage policy. Anon key is public-safe by design. Policies are our responsibility but simple and auditable. |
| Maintenance | Dual migrations (local + remote schema) and sync code to maintain. Moderate. Managed sync (below) reduces this. |
| Cost | Free tier: ~500 MB DB, 1 GB storage, 50k MAU — comfortable for beta. Pro $25/mo if exceeded. |

**Managed-sync variant worth flagging:** PowerSync (Postgres↔SQLite sync
engine with a Flutter SDK) replaces most of §5.6 custom code — handles
delta sync, queueing, and conflict-adjacent plumbing. Cost: extra
dependency + hosted tier pricing; sync rules written in its DSL. Sensible
upgrade if hand-rolled sync proves fragile; the rest of the architecture
(auth, ownership, storage) is unchanged either way.

## Option 2 — Firebase Auth + Firestore

Only viable as **full replacement**: if SQLite stays as the UI store and
Firestore is added behind it, we write the same custom sync engine as
Option 1 *plus* a relational↔document impedance mismatch — strictly worse.
So this option means: Firestore becomes the primary store (its built-in
offline cache replaces SQLite's role).

| Criterion | Assessment |
|---|---|
| Migration effort | **High.** Denormalize 15 relational tables into collections/documents; rewrite every query, stats query and service; migrate v28 history into document shape. Effectively a data-layer rewrite. SQL conveniences lost: no joins, no LIKE/ILIKE, limited aggregation — catch statistics become client-side composition or pre-aggregated counters to maintain. |
| Offline reliability | **Excellent** — the one clear technical advantage. Firestore's offline persistence (cache reads + write queue + automatic replay) is best-in-class and would remove our sync engine entirely. |
| Multi-device conflicts | Automatic last-writer-wins per document; transactions available. Whole-document granularity only — coarser than our row-level LWW but adequate. |
| Media sync | Cloud Storage for Firebase, resumable uploads with retry — comparable to Supabase Storage. |
| Security | Firestore security rules (`auth.uid() == resource.data.owner_id`) — mature, well-documented, comparable to RLS. |
| Maintenance | Lowest *sync* maintenance (SDK does it). Highest *data-model* maintenance — every new feature re-litigates denormalization, counters, and query workarounds. |
| Cost | Spark free tier generous (50k reads/day, 20k writes/day, 1 GB storage). Blaze is per-operation billing — chatty read/write patterns and media egress can surprise, though beta scale is unlikely to hit it. |

**Verdict:** the offline engine is genuinely better, but we already own a
working data layer; trading a bounded sync-engine build for a full data-
layer rewrite + permanent document-modeling tax is a bad trade for this
app.

## Option 3 — Hybrid: Firebase Auth + PostgreSQL

Firebase Auth's distinctive strengths are phone-number auth, anonymous
auth and a broad OAuth matrix — none of which this beta needs (email +
password suffices, and any OAuth triggers Apple's Sign-in-with-Apple
requirement anyway).

The cost is architectural friction: Supabase RLS keys off `auth.uid()`
from Supabase-issued JWTs. With Firebase Auth we must bridge identity —
verify Firebase ID tokens in edge functions, or configure external-JWT
trust — which either bypasses RLS (losing Option 1's security model) or
adds a token-minting/verifying hop on every data path. Two vendor
consoles, two SDKs, and the hardest-to-debug failure modes (token expiry
skew between providers) for zero feature gain at beta scale.

**Verdict:** no compelling reason. Revisit only if phone auth or a
specific OAuth provider matrix becomes a requirement — at which point the
migration is auth-layer-only and doesn't invalidate the Postgres/SQLite
data architecture.

---

## Recommendation

**Proceed with Option 1** (the existing proposal), with two refinements:

1. Keep the sync engine hand-rolled LWW for beta (simple, auditable), but
   note PowerSync as the escape hatch if sync complexity grows.
2. All nine decisions in the architecture doc stand unchanged; this
   comparison resolves the underlying platform question in Option 1's
   favour.
