import crypto from 'node:crypto';
import { config } from './config.js';

/**
 * Lightweight client identity for the MVP.
 *
 * The device generates a random install id, exchanges it once for a signed,
 * expiring token, and sends that token as a bearer credential afterwards.
 *
 * What this IS: enough to attribute rate limits and usage to a client, and a
 * seam that a real account system drops into later without the iOS side
 * changing shape.
 *
 * What this is NOT: proof of who the human is. It does not need to be for a
 * demo, and pretending otherwise would be worse than saying so. The important
 * property is the one the brief asks for - the OpenAI credential is never the
 * thing the client holds.
 */

function base64url(buffer) {
  return Buffer.from(buffer).toString('base64url');
}

function sign(payloadB64) {
  return crypto
    .createHmac('sha256', config.auth.signingSecret)
    .update(payloadB64)
    .digest('base64url');
}

/** Stable, non-reversible client id. The raw install id is never stored. */
export function clientIdFromInstallId(installId) {
  return crypto
    .createHmac('sha256', config.auth.signingSecret)
    .update(`install:${installId}`)
    .digest('hex')
    .slice(0, 32);
}

export function issueToken(installId) {
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    sub: clientIdFromInstallId(installId),
    iat: now,
    exp: now + config.auth.tokenTTLSeconds,
    v: 1
  };
  const payloadB64 = base64url(JSON.stringify(payload));
  return {
    token: `${payloadB64}.${sign(payloadB64)}`,
    expiresAt: payload.exp
  };
}

/** Returns the client id, or null when the token is absent, forged or stale. */
export function verifyToken(token) {
  if (typeof token !== 'string') return null;
  const dot = token.indexOf('.');
  if (dot < 1) return null;

  const payloadB64 = token.slice(0, dot);
  const signature = token.slice(dot + 1);
  const expected = sign(payloadB64);

  // Constant-time compare. Length check first, because timingSafeEqual throws
  // on a length mismatch rather than returning false.
  if (signature.length !== expected.length) return null;
  if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) {
    return null;
  }

  let payload;
  try {
    payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString('utf8'));
  } catch {
    return null;
  }

  if (!payload || typeof payload.sub !== 'string') return null;
  if (typeof payload.exp !== 'number' || payload.exp < Date.now() / 1000) return null;
  return payload.sub;
}

export function bearerFrom(req) {
  const header = req.headers['authorization'];
  if (typeof header !== 'string') return null;
  const match = /^Bearer (.+)$/.exec(header.trim());
  return match ? match[1] : null;
}
