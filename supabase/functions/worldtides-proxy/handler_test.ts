// Deno tests for worldtides-proxy handler — fully mocked deps; no live
// Supabase, no WorldTides calls, no real API key.
//
// Run: deno test --allow-env supabase/functions/worldtides-proxy/
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { handler, parseParams, ProxyDeps } from './handler.ts';

const UID = '11111111-2222-3333-4444-555555555555';
const FAKE_KEY = 'TEST-KEY-NOT-REAL';

const VALID_BODY = {
  lat: -12.4634,
  lon: 130.8446,
  date: '2026-10-20',
  days: 3,
  datum: 'CD',
};

function req(body: unknown = VALID_BODY, auth = 'Bearer test.jwt') {
  return new Request('https://fn.test/worldtides-proxy', {
    method: 'POST',
    headers: auth ? { Authorization: auth } : {},
    body: JSON.stringify(body),
  });
}

interface Mocked {
  deps: ProxyDeps;
  upstreamUrls: string[];
  releases: string[];
}

function mockedDeps(overrides: Partial<ProxyDeps> = {}): Mocked {
  const upstreamUrls: string[] = [];
  const releases: string[] = [];
  const deps: ProxyDeps = {
    getUserId: async () => UID,
    isApprovedBeta: async () => true,
    reserveCredit: async () => 'ok',
    releaseCredit: async (uid) => {
      releases.push(uid);
    },
    getApiKey: () => FAKE_KEY,
    fetchUpstream: async (url) => {
      upstreamUrls.push(url);
      return new Response(
        JSON.stringify({
          status: 200,
          callCount: 1,
          extremes: [{ type: 'High', date: '2026-10-20T08:00:00Z', height: 6.4 }],
          atlas: 'FES2022',
          copyright: 'Tidal data © WorldTides',
          // Noise fields that must NOT be forwarded:
          internalDebug: 'server-details',
        }),
        { status: 200 },
      );
    },
    ...overrides,
  };
  return { deps, upstreamUrls, releases };
}

// ── Authentication & entitlement ───────────────────────────────────────

Deno.test('rejects missing Authorization header', async () => {
  const { deps } = mockedDeps();
  const res = await handler(req(VALID_BODY, ''), deps);
  assertEquals(res.status, 401);
});

Deno.test('rejects invalid session', async () => {
  const { deps } = mockedDeps({ getUserId: async () => null });
  const res = await handler(req(), deps);
  assertEquals(res.status, 401);
});

Deno.test('rejects unapproved / revoked beta user', async () => {
  const { deps } = mockedDeps({ isApprovedBeta: async () => false });
  const res = await handler(req(), deps);
  assertEquals(res.status, 403);
});

Deno.test('entitlement is checked on every request (per-request call)',
    async () => {
  let checks = 0;
  const { deps } = mockedDeps({
    isApprovedBeta: async () => {
      checks++;
      return true;
    },
  });
  await handler(req(), deps);
  assertEquals(checks, 1);
});

// ── Valid approved user ────────────────────────────────────────────────

Deno.test('valid approved user gets whitelisted prediction fields',
    async () => {
  const { deps, upstreamUrls } = mockedDeps();
  const res = await handler(req(), deps);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.extremes.length, 1);
  assertEquals(body.atlas, 'FES2022');
  // Whitelist: noise/debug fields and the key never reach the client.
  assertEquals(body.internalDebug, undefined);
  assertEquals(JSON.stringify(body).includes(FAKE_KEY), false);
  // Upstream URL carries the key; request params are passed through.
  assertEquals(upstreamUrls.length, 1);
  assertEquals(upstreamUrls[0].includes(`key=${FAKE_KEY}`), true);
  assertEquals(upstreamUrls[0].includes('lat=-12.4634'), true);
});

// ── Parameter validation ───────────────────────────────────────────────

Deno.test('rejects invalid params without touching upstream', async () => {
  const cases: unknown[] = [
    { ...VALID_BODY, lat: 91 },
    { ...VALID_BODY, lat: 'x' },
    { ...VALID_BODY, lon: -181 },
    { ...VALID_BODY, date: '20-10-2026' },
    { ...VALID_BODY, date: '1990-01-01' }, // outside allowed window
    { ...VALID_BODY, days: 8 },
    { ...VALID_BODY, days: 0 },
    { ...VALID_BODY, datum: 'MLLW' },
    { ...VALID_BODY, extremes: false, op: 'heights' }, // unsupported op
    'not-an-object',
  ];
  for (const body of cases) {
    const { deps, upstreamUrls } = mockedDeps();
    const res = await handler(req(body), deps);
    assertEquals(res.status, 400, `expected 400 for ${JSON.stringify(body)}`);
    assertEquals(upstreamUrls.length, 0);
  }
});

Deno.test('parseParams boundary cases', () => {
  const now = new Date('2026-10-22T00:00:00Z').getTime();
  assertEquals(
    parseParams({ lat: 90, lon: 180, date: '2026-10-22' }, now) !== null,
    true,
  );
  assertEquals(parseParams({ lat: -12, lon: 130, date: '2026-10-22' }, now)
      ?.days, 3);
  assertEquals(parseParams({ lat: -12, lon: 130, date: '2026-10-22' }, now)
      ?.datum, 'CD');
});

// ── Quotas ─────────────────────────────────────────────────────────────

Deno.test('user quota exhaustion returns 429 without upstream call',
    async () => {
  const { deps, upstreamUrls } = mockedDeps({
    reserveCredit: async () => 'user_quota',
  });
  const res = await handler(req(), deps);
  assertEquals(res.status, 429);
  assertEquals(upstreamUrls.length, 0);
});

Deno.test('global quota exhaustion returns 429 without upstream call',
    async () => {
  const { deps } = mockedDeps({ reserveCredit: async () => 'global_quota' });
  const res = await handler(req(), deps);
  assertEquals(res.status, 429);
});

// ── Upstream failures & reconciliation ────────────────────────────────

Deno.test('upstream error body is sanitised (no key/details leak)',
    async () => {
  const { deps } = mockedDeps({
    fetchUpstream: async () =>
      new Response(
        JSON.stringify({ error: `Invalid key ${FAKE_KEY} at lat=-12.4634` }),
        { status: 400 },
      ),
  });
  const res = await handler(req(), deps);
  assertEquals(res.status, 502);
  const body = await res.json();
  assertEquals(JSON.stringify(body).includes(FAKE_KEY), false);
  assertEquals(JSON.stringify(body).includes('lat'), false);
  assertEquals(body.error, 'tide service unavailable');
});

Deno.test('upstream network failure keeps the reservation (conservative)',
    async () => {
  const { deps, releases } = mockedDeps({
    fetchUpstream: async () => {
      throw new Error('timeout');
    },
  });
  const res = await handler(req(), deps);
  assertEquals(res.status, 502);
  assertEquals(releases.length, 0);
});

Deno.test('callCount === 0 (unbilled) releases the reservation', async () => {
  const { deps, releases } = mockedDeps({
    fetchUpstream: async () =>
      new Response(
        JSON.stringify({ status: 400, callCount: 0, error: 'no data' }),
        { status: 200 },
      ),
  });
  await handler(req(), deps);
  assertEquals(releases, [UID]);
});

Deno.test('missing server key fails closed without leaking config',
    async () => {
  const { deps } = mockedDeps({ getApiKey: () => undefined });
  const res = await handler(req(), deps);
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error, 'tide service not configured');
});

Deno.test('OPTIONS preflight and non-POST methods', async () => {
  const { deps } = mockedDeps();
  const opt = await handler(
    new Request('https://fn.test/x', { method: 'OPTIONS' }), deps);
  assertEquals(opt.status, 200);
  const get = await handler(
    new Request('https://fn.test/x', { method: 'GET' }), deps);
  assertEquals(get.status, 405);
});
