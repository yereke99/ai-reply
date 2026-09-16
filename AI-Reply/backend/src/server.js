import http from 'node:http';
import { config, assertConfigured } from './config.js';
import { bearerFrom, issueToken, verifyToken } from './auth.js';
import { consume } from './rateLimit.js';
import { ErrorCode, normalizeReplyRequest } from './validate.js';
import { buildPrompt } from './prompt.js';
import { generateReply, UpstreamError } from './openai.js';
import { detectLanguage } from './language.js';
import { recordFailure, recordSuccess, snapshot } from './metrics.js';

const MAX_BODY_BYTES = 16 * 1024;

function send(res, status, payload, extraHeaders = {}) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
    ...extraHeaders
  });
  res.end(body);
}

function fail(res, status, code, extra = {}, headers = {}) {
  // Only a stable code and safe numeric detail ever crosses this boundary.
  // Upstream messages, stack traces and key material never do.
  send(res, status, { error: { code, ...extra } }, headers);
}

function readJSONBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(new Error('body_too_large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (chunks.length === 0) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        reject(new Error('invalid_json'));
      }
    });
    req.on('error', reject);
  });
}

// MARK: Routes

async function handleRegister(req, res) {
  let body;
  try {
    body = await readJSONBody(req);
  } catch {
    return fail(res, 400, ErrorCode.invalidRequest);
  }

  const installId = typeof body.install_id === 'string' ? body.install_id.trim() : '';
  // A UUID string. Anything shorter is not a real install id.
  if (installId.length < 16 || installId.length > 128) {
    return fail(res, 400, ErrorCode.invalidRequest);
  }

  const { token, expiresAt } = issueToken(installId);
  send(res, 200, { token, expires_at: expiresAt });
}

async function handleGenerate(req, res) {
  const startedAt = Date.now();

  const clientId = verifyToken(bearerFrom(req));
  if (!clientId) {
    return fail(res, 401, ErrorCode.unauthorized);
  }

  const limit = consume(clientId);
  if (!limit.allowed) {
    recordFailure({ clientId, code: ErrorCode.rateLimited, durationMs: 0 });
    return fail(
      res,
      429,
      ErrorCode.rateLimited,
      { scope: limit.scope, retry_after_seconds: limit.retryAfterSeconds },
      { 'Retry-After': String(limit.retryAfterSeconds) }
    );
  }

  let body;
  try {
    body = await readJSONBody(req);
  } catch {
    recordFailure({ clientId, code: ErrorCode.invalidRequest, durationMs: 0 });
    return fail(res, 400, ErrorCode.invalidRequest);
  }

  const normalized = normalizeReplyRequest(body);
  if (!normalized.ok) {
    recordFailure({ clientId, code: normalized.code, durationMs: 0 });
    const status = normalized.code === ErrorCode.messageTooLong ? 413 : 400;
    return fail(res, status, normalized.code, normalized.detail ?? {});
  }

  try {
    const { reply, usage, model } = await generateReply(buildPrompt(normalized.value));
    const durationMs = Date.now() - startedAt;
    recordSuccess({ clientId, model, usage, durationMs });
    send(res, 200, { reply, detected_language: detectLanguage(reply) });
  } catch (error) {
    const durationMs = Date.now() - startedAt;
    const code = error instanceof UpstreamError ? error.code : ErrorCode.internal;
    const status = error instanceof UpstreamError ? error.status : 500;
    recordFailure({ clientId, code, durationMs });
    // Logged WITHOUT any payload: code and timing only.
    console.error(`[generate] ${code} status=${status} duration=${durationMs}ms`);
    fail(res, status, code);
  }
}

// MARK: Server

const server = http.createServer((req, res) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);

  if (req.method === 'GET' && url.pathname === '/healthz') {
    return send(res, 200, { ok: true, model: config.openAI.model });
  }
  if (req.method === 'GET' && url.pathname === '/v1/usage') {
    return send(res, 200, snapshot());
  }
  if (req.method === 'POST' && url.pathname === '/v1/auth/register') {
    return handleRegister(req, res).catch(() => fail(res, 500, ErrorCode.internal));
  }
  if (req.method === 'POST' && url.pathname === '/v1/reply/generate') {
    return handleGenerate(req, res).catch(() => fail(res, 500, ErrorCode.internal));
  }

  fail(res, 404, ErrorCode.invalidRequest);
});

const problems = assertConfigured();
if (problems.length > 0) {
  console.error('Refusing to start. Fix backend/.env:');
  for (const problem of problems) console.error(`  - ${problem}`);
  console.error('\nSee backend/.env.example.');
  process.exit(1);
}

server.listen(config.port, config.host, () => {
  console.log(`AI Reply backend on http://${config.host}:${config.port}`);
  console.log(`Model: ${config.openAI.model}  |  max output tokens: ${config.openAI.maxOutputTokens}`);
  console.log(`Message limit: ${config.limits.messageCharacters} characters`);
});
