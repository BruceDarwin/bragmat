// Stage 4C-1 — delete-backups Edge Function
//
// Deletes the CALLER'S cloud backup objects via the Storage API (service
// role, server-side only), so physical objects are actually removed —
// never delete storage.objects rows directly (that orphans files).
//
// Security contract:
//   * Caller identity comes from the Authorization Bearer JWT, verified
//     against Supabase Auth — never from request parameters.
//   * Deletion is hard-scoped to `{caller uid}/` — the prefix is built
//     server-side from the verified uid; a caller can never reach
//     another user's objects.
//   * is_approved_beta() is deliberately NOT checked: a revoked tester
//     must still be able to remove their backups (account closure).
//   * The service-role key exists only as the function's environment —
//     it is never shipped to or seen by the client.
//   * Optional JSON body { "name": "<file>.bzp" } deletes a single named
//     backup; omitted = delete all of the caller's backups. The name is
//     validated to be a bare filename — no separators or traversal.
//   * Auditing writes user_id + count + reason to
//     public.backup_deletion_audit. Nothing sensitive is logged: no
//     passphrases, keys, plaintext, or location data ever appear here.
//
// Deno / Supabase Edge Functions runtime.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST' && req.method !== 'DELETE') {
    return json(405, { error: 'method not allowed' });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return json(401, { error: 'missing authorization' });
  }

  // ── Authenticate the caller server-side ─────────────────────────────
  const userClient = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: userData, error: userError } =
    await userClient.auth.getUser();
  if (userError || !userData.user) {
    return json(401, { error: 'invalid session' });
  }
  const uid = userData.user.id;

  // ── Parse optional single-object target ─────────────────────────────
  let singleName: string | null = null;
  let reason = 'user_request';
  try {
    const body = await req.json().catch(() => ({}));
    if (body && typeof body.name === 'string' && body.name.length > 0) {
      // Bare filenames only — no path separators or traversal.
      if (/[/\\]|\.\./.test(body.name) || body.name.length > 200) {
        return json(400, { error: 'invalid backup name' });
      }
      singleName = body.name;
    }
    if (body && body.reason === 'account_closure') {
      reason = 'account_closure';
    }
  } catch (_) {
    // No/invalid JSON body → delete-all default; not an error.
  }

  const prefix = `${uid}/`;
  const admin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  // ── Resolve the target paths (always under the caller's prefix) ─────
  let paths: string[];
  if (singleName !== null) {
    paths = [`${prefix}${singleName}`];
  } else {
    const { data: listed, error: listError } = await admin.storage
      .from('backups')
      .list(prefix, { limit: 1000 });
    if (listError) {
      console.error('delete-backups: list failed', listError.message);
      return json(502, { error: 'storage list failed' });
    }
    paths = (listed ?? [])
      .filter((o) => o.name && o.name.length > 0)
      .map((o) => `${prefix}${o.name}`);
  }
  if (paths.length === 0) {
    return json(200, { deleted: 0 });
  }

  // ── Delete through the Storage API ──────────────────────────────────
  const { data: removed, error: removeError } = await admin.storage
    .from('backups')
    .remove(paths);
  if (removeError) {
    console.error('delete-backups: remove failed', removeError.message);
    return json(502, { error: 'storage delete failed' });
  }

  // ── Verify deletion through the API ─────────────────────────────────
  const { data: after } = await admin.storage
    .from('backups')
    .list(prefix, { limit: 1000 });
  const survivors = new Set((after ?? []).map((o) => `${prefix}${o.name}`));
  const stillPresent = paths.filter((p) => survivors.has(p));
  if (stillPresent.length > 0) {
    console.error(
      `delete-backups: ${stillPresent.length} object(s) still present after remove`,
    );
    return json(502, { error: 'deletion verification failed' });
  }
  const deletedCount = removed?.length ?? paths.length;

  // ── Audit (counts + identity only — no filenames or content) ────────
  const { error: auditError } = await admin
    .from('backup_deletion_audit')
    .insert({ user_id: uid, deleted_count: deletedCount, reason });
  if (auditError) {
    // Deletion already happened and is verified — audit failure is
    // logged but does not fail the request.
    console.error('delete-backups: audit insert failed', auditError.message);
  }

  return json(200, { deleted: deletedCount });
});
