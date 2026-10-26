// WT2 — worldtides-proxy Edge Function entrypoint.
// Request logic lives in handler.ts so it stays unit-testable without
// binding a port; see that file for the full security contract.
// NOTE: Deno.serve invokes its callback as (request, info) — the wrapper
// lambda is required so `info` is never mistaken for handler deps.
import { handler } from './handler.ts';

Deno.serve((req) => handler(req));
