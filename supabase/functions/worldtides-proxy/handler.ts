// WT2 — worldtides-proxy request handler.
//
// Security contract:
//   * Caller identity comes from the Authorization Bearer JWT, verified
//     against Supabase Auth — never from request parameters.
//   * public.is_approved_beta() is enforced on EVERY request — a revoked
//     tester is rejected immediately (403), matching the entitlement
//     precedent in migrations 0001/0002.
//   * The WorldTides key is read ONLY from the WORLDTIDES_API_KEY
//     environment secret. It is never logged, never returned, and
//     upstream error bodies are sanitised because they can echo request
//     parameters (including key=) back to the caller.
//   * Only the tide-extremes operation is supported, with parameters the
//     app actually sends: lat, lon, date, days (1–7), datum ('CD').
//   * Credit budgets are reserved atomically BEFORE the upstream call via
//     public.worldtides_reserve_credit() (service role only). A failed or
//     indeterminate upstream call keeps the reservation — conservative
//     billing beats under-charging. Upstream responses reporting
//     callCount === 0 (not billed) release it via
//     public.worldtides_release_credit().
//   * Usage counters store (user_id, cycle, credits) only — request
//     coordinates exist only transiently inside this request and are
//     never persisted or logged.
//
// The handler takes injectable deps so tests can exercise auth,
// entitlement, quotas and upstream behaviour without a live Supabase
// project or the real WorldTides API.
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const WORLDTIDES_URL = 'https://www.worldtides.info/api/v3';
const UPSTREAM_TIMEOUT_MS = 25_000;

export function json(
  status: number,
  body: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// ── Parameter validation ──────────────────────────────────────────────
export function parseParams(
  body: Record<string, unknown>,
  now = Date.now(),
) {
  // Strict allowlist: the only keys the proxy accepts. Anything else —
  // e.g. an attempt to select a different WorldTides operation — is
  // rejected outright.
  for (const key of Object.keys(body)) {
    if (!['lat', 'lon', 'date', 'days', 'datum'].includes(key)) {
      return null;
    }
  }

  const lat = body.lat;
  const lon = body.lon;
  const date = body.date;
  const days = body.days ?? 3;
  const datum = body.datum ?? 'CD';

  if (typeof lat !== 'number' || !Number.isFinite(lat) || Math.abs(lat) > 90) {
    return null;
  }
  if (typeof lon !== 'number' || !Number.isFinite(lon) || Math.abs(lon) > 180) {
    return null;
  }
  if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return null;
  }
  const parsed = new Date(`${date}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime())) return null;
  // Historical lookups are legitimate (old catches); bound the window to
  // 10 years back / 3 months ahead to reject absurd input without
  // breaking those.
  const TEN_YEARS_MS = 10 * 365.25 * 24 * 3600 * 1000;
  const THREE_MONTHS_MS = 92 * 24 * 3600 * 1000;
  if (
    parsed.getTime() < now - TEN_YEARS_MS ||
    parsed.getTime() > now + THREE_MONTHS_MS
  ) {
    return null;
  }
  if (
    typeof days !== 'number' ||
    !Number.isInteger(days) ||
    days < 1 ||
    days > 7
  ) {
    return null;
  }
  // Only the chart datum the app uses; other values would change the
  // meaning of stored heights.
  if (datum !== 'CD') return null;

  return { lat, lon, date, days, datum };
}

export interface ProxyDeps {
  /** Returns the authenticated user id for a Bearer header, or null. */
  getUserId: (authHeader: string) => Promise<string | null>;
  /** public.is_approved_beta() under the caller's role. */
  isApprovedBeta: (authHeader: string) => Promise<boolean>;
  /** Atomic reservation; returns 'ok' | 'user_quota' | 'global_quota' | 'error'. */
  reserveCredit: (uid: string) => Promise<string>;
  /** Releases a reservation when upstream reports callCount === 0. */
  releaseCredit: (uid: string) => Promise<void>;
  /** Server-side WorldTides key; undefined when not configured. */
  getApiKey: () => string | undefined;
  /** The upstream HTTP call (mockable). */
  fetchUpstream: (url: string) => Promise<Response>;
}

export function defaultDeps(): ProxyDeps {
  const userClientFor = (authHeader: string): SupabaseClient =>
    createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    );

  const admin = (): SupabaseClient =>
    createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

  return {
    getUserId: async (authHeader) => {
      const { data, error } = await userClientFor(authHeader).auth.getUser();
      return error || !data.user ? null : data.user.id;
    },
    isApprovedBeta: async (authHeader) => {
      const { data, error } =
        await userClientFor(authHeader).rpc('is_approved_beta');
      return !error && data === true;
    },
    reserveCredit: async (uid) => {
      const { data, error } = await admin().rpc('worldtides_reserve_credit', {
        p_user: uid,
      });
      if (error) {
        console.error('worldtides-proxy: reservation failed', error.message);
        return 'error';
      }
      return typeof data === 'string' ? data : 'error';
    },
    releaseCredit: async (uid) => {
      const { error } = await admin().rpc('worldtides_release_credit', {
        p_user: uid,
      });
      if (error) {
        console.error('worldtides-proxy: release failed', error.message);
      }
    },
    getApiKey: () => Deno.env.get('WORLDTIDES_API_KEY'),
    fetchUpstream: (url) =>
      fetch(url, { signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS) }),
  };
}

export async function handler(
  req: Request,
  deps: ProxyDeps = defaultDeps(),
): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json(405, { error: 'method not allowed' });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return json(401, { error: 'missing authorization' });
  }

  // ── Authenticate the caller server-side ─────────────────────────────
  const uid = await deps.getUserId(authHeader);
  if (!uid) {
    return json(401, { error: 'invalid session' });
  }

  // ── Beta entitlement — every request, including revoked testers ─────
  if (!(await deps.isApprovedBeta(authHeader))) {
    return json(403, { error: 'not an approved beta tester' });
  }

  // ── Validate the request body ───────────────────────────────────────
  let params;
  try {
    const body = await req.json();
    params = body && typeof body === 'object' ? parseParams(body) : null;
  } catch (_) {
    params = null;
  }
  if (!params) {
    return json(400, { error: 'invalid parameters' });
  }

  const apiKey = deps.getApiKey();
  if (!apiKey) {
    console.error('worldtides-proxy: WORLDTIDES_API_KEY secret not set');
    return json(500, { error: 'tide service not configured' });
  }

  // ── Atomic credit reservation (server-side budget enforcement) ──────
  const reservation = await deps.reserveCredit(uid);
  if (reservation === 'user_quota' || reservation === 'global_quota') {
    return json(429, { error: 'tide credit budget exceeded' });
  }
  if (reservation !== 'ok') {
    return json(502, { error: 'tide service unavailable' });
  }

  // ── Upstream call — the key exists only inside this URL string and
  // is never logged or forwarded in a response. ─────────────────────────
  const url = new URL(WORLDTIDES_URL);
  url.search = new URLSearchParams({
    extremes: '',
    lat: String(params.lat),
    lon: String(params.lon),
    date: params.date,
    days: String(params.days),
    datum: params.datum,
    key: apiKey,
  }).toString();

  let upstream: Response;
  try {
    upstream = await deps.fetchUpstream(url.toString());
  } catch (_) {
    // Timeout/network failure — billing indeterminate; keep reservation.
    console.error('worldtides-proxy: upstream request failed');
    return json(502, { error: 'tide service unavailable' });
  }

  let upstreamBody: Record<string, unknown> | null = null;
  try {
    upstreamBody = await upstream.json();
  } catch (_) {
    upstreamBody = null;
  }

  // ── Reconciliation: release the reservation only when WorldTides
  // explicitly reports the call as unbilled (callCount === 0). Any
  // other failure or ambiguity keeps it. ───────────────────────────────
  if (upstreamBody && upstreamBody.callCount === 0) {
    await deps.releaseCredit(uid);
  }

  // ── Sanitised passthrough — whitelist prediction fields only. Never
  // forward raw upstream bodies: error payloads can echo request
  // parameters (including the key) and internal details. ───────────────
  if (!upstream.ok || !upstreamBody || upstreamBody.error) {
    console.error(`worldtides-proxy: upstream status=${upstream.status}`);
    return json(502, { error: 'tide service unavailable' });
  }

  return json(200, {
    status: upstreamBody.status,
    extremes: upstreamBody.extremes,
    station: upstreamBody.station,
    atlas: upstreamBody.atlas,
    responseLat: upstreamBody.responseLat,
    responseLon: upstreamBody.responseLon,
    copyright: upstreamBody.copyright,
    reqLat: upstreamBody.reqLat,
    reqLon: upstreamBody.reqLon,
    date: upstreamBody.date,
  });
}
