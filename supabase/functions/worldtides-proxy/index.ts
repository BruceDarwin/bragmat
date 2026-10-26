// WT2 — worldtides-proxy Edge Function entrypoint.
// Request logic lives in handler.ts so it stays unit-testable without
// binding a port; see that file for the full security contract.
import { handler } from './handler.ts';

Deno.serve(handler);
