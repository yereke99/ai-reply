import { config } from './config.js';

/**
 * Per-client sliding-window rate limiting, held in memory.
 *
 * In memory is the right call for a single-process demo and the wrong call for
 * a real deployment behind more than one instance - swap the two maps for Redis
 * and nothing else here changes. Saying that plainly beats shipping something
 * that looks distributed and is not.
 */

const MINUTE_MS = 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

/** clientId -> array of request timestamps (ms). */
const hits = new Map();

/** Drops clients that have not been seen for a day so the map cannot grow forever. */
function sweep(now) {
  for (const [clientId, timestamps] of hits) {
    const live = timestamps.filter((t) => now - t < DAY_MS);
    if (live.length === 0) hits.delete(clientId);
    else hits.set(clientId, live);
  }
}

let lastSweep = 0;

/**
 * @returns {{allowed: true} | {allowed: false, scope: 'minute'|'day', retryAfterSeconds: number}}
 */
export function consume(clientId) {
  const now = Date.now();

  if (now - lastSweep > 10 * MINUTE_MS) {
    lastSweep = now;
    sweep(now);
  }

  const timestamps = (hits.get(clientId) ?? []).filter((t) => now - t < DAY_MS);

  const inLastMinute = timestamps.filter((t) => now - t < MINUTE_MS);
  if (inLastMinute.length >= config.limits.perMinute) {
    hits.set(clientId, timestamps);
    const oldest = inLastMinute[0];
    return {
      allowed: false,
      scope: 'minute',
      retryAfterSeconds: Math.max(1, Math.ceil((MINUTE_MS - (now - oldest)) / 1000))
    };
  }

  if (timestamps.length >= config.limits.perDay) {
    hits.set(clientId, timestamps);
    const oldest = timestamps[0];
    return {
      allowed: false,
      scope: 'day',
      retryAfterSeconds: Math.max(1, Math.ceil((DAY_MS - (now - oldest)) / 1000))
    };
  }

  timestamps.push(now);
  hits.set(clientId, timestamps);
  return { allowed: true };
}

/** Test seam. */
export function reset() {
  hits.clear();
  lastSweep = 0;
}
