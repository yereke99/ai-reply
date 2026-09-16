import { config } from './config.js';

/**
 * Aggregate cost accounting.
 *
 * Records token counts, model, duration and outcome. It deliberately records
 * NO message text, NO profile text, NO reply text and no raw install id - the
 * client id it keys on is already a one-way HMAC. That is enough to compute
 * cost per active user and nowhere near enough to reconstruct a conversation.
 */

const totals = {
  startedAt: new Date().toISOString(),
  requests: 0,
  succeeded: 0,
  failed: 0,
  inputTokens: 0,
  outputTokens: 0,
  durationMsTotal: 0,
  byModel: {},
  clients: new Set()
};

export function recordSuccess({ clientId, model, usage, durationMs }) {
  totals.requests += 1;
  totals.succeeded += 1;
  totals.inputTokens += usage.inputTokens;
  totals.outputTokens += usage.outputTokens;
  totals.durationMsTotal += durationMs;
  totals.clients.add(clientId);

  const entry = (totals.byModel[model] ??= { requests: 0, inputTokens: 0, outputTokens: 0 });
  entry.requests += 1;
  entry.inputTokens += usage.inputTokens;
  entry.outputTokens += usage.outputTokens;
}

export function recordFailure({ clientId, code, durationMs }) {
  totals.requests += 1;
  totals.failed += 1;
  totals.durationMsTotal += durationMs;
  if (clientId) totals.clients.add(clientId);
  const entry = (totals.byModel.failures ??= {});
  entry[code] = (entry[code] ?? 0) + 1;
}

export function snapshot() {
  const { clients, ...rest } = totals;
  return {
    ...rest,
    model: config.openAI.model,
    distinctClients: clients.size,
    averageDurationMs:
      totals.requests > 0 ? Math.round(totals.durationMsTotal / totals.requests) : 0
  };
}
