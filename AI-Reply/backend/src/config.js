import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const rootDir = join(here, '..');

/**
 * Minimal .env reader.
 *
 * Deliberately hand-rolled rather than a dependency: this project has zero
 * npm dependencies so `npm install` is not a prerequisite for running the
 * demo. Values already present in the real process environment always win, so
 * a deployment that injects secrets properly (systemd, Docker, a secret
 * manager) never needs a .env file at all.
 */
function loadDotEnv() {
  let raw;
  try {
    raw = readFileSync(join(rootDir, '.env'), 'utf8');
  } catch {
    return;
  }
  for (const line of raw.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq < 1) continue;
    const key = trimmed.slice(0, eq).trim();
    if (key in process.env) continue;
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    process.env[key] = value;
  }
}

loadDotEnv();

function int(name, fallback) {
  const value = Number.parseInt(process.env[name] ?? '', 10);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

export const config = {
  host: process.env.HOST || '0.0.0.0',
  port: int('PORT', 8787),

  openAI: {
    // Read from the environment at startup and never written anywhere else.
    apiKey: process.env.OPENAI_API_KEY || '',
    // Single source of truth for the model. No iOS source file names a model.
    model: process.env.OPENAI_MODEL || 'gpt-4o-mini',
    maxOutputTokens: int('OPENAI_MAX_OUTPUT_TOKENS', 180),
    timeoutMs: int('OPENAI_TIMEOUT_MS', 20000),
    baseURL: process.env.OPENAI_BASE_URL || 'https://api.openai.com/v1'
  },

  auth: {
    signingSecret: process.env.AUTH_SIGNING_SECRET || '',
    tokenTTLSeconds: int('AUTH_TOKEN_TTL_SECONDS', 60 * 60 * 24 * 30)
  },

  limits: {
    // Mirrors the client-side cap. The client limit is a courtesy; this one is
    // the rule, because a client can always be modified.
    messageCharacters: 300,
    profileCharacters: 1000,
    profileRoleCharacters: 120,
    businessOfferingCharacters: 120,
    businessSummaryCharacters: 400,
    businessRuleCharacters: 200,
    businessRules: 8,
    templateInstructionCharacters: 600,
    templateNameCharacters: 60,
    perMinute: int('RATE_LIMIT_PER_MINUTE', 12),
    perDay: int('RATE_LIMIT_PER_DAY', 200)
  }
};

/** Startup validation. Failing loudly here beats failing per-request later. */
export function assertConfigured() {
  const problems = [];
  if (!config.openAI.apiKey) {
    problems.push('OPENAI_API_KEY is not set');
  } else if (!config.openAI.apiKey.startsWith('sk-')) {
    problems.push('OPENAI_API_KEY does not look like an OpenAI key');
  }
  if (!config.auth.signingSecret || config.auth.signingSecret.length < 32) {
    problems.push('AUTH_SIGNING_SECRET must be at least 32 characters');
  }
  return problems;
}
