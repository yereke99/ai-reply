import { config } from './config.js';
import { ErrorCode } from './validate.js';

/**
 * The one place in this repository that talks to OpenAI, and the one place the
 * credential is read. Uses the Responses API.
 */

export class UpstreamError extends Error {
  constructor(code, status, detail) {
    super(code);
    this.code = code;
    this.status = status;
    this.detail = detail;
  }
}

/** Pulls the assistant text out of a Responses API payload. */
function extractText(payload) {
  // `output_text` is an SDK convenience and is not guaranteed over raw HTTP,
  // so the structured path is the primary one.
  if (Array.isArray(payload?.output)) {
    const chunks = [];
    for (const item of payload.output) {
      if (item?.type !== 'message') continue;
      for (const part of item.content ?? []) {
        if (part?.type === 'output_text' && typeof part.text === 'string') {
          chunks.push(part.text);
        }
      }
    }
    const joined = chunks.join('').trim();
    if (joined) return joined;
  }
  if (typeof payload?.output_text === 'string') return payload.output_text.trim();
  return '';
}

/**
 * Strips the wrapper a chat model sometimes puts around a one-line answer.
 * Conservative: only removes a matched pair that encloses the WHOLE reply, so
 * a quotation inside a genuine sentence survives.
 */
function unwrapQuotes(text) {
  const pairs = [
    ['"', '"'],
    ['“', '”'],
    ['«', '»'],
    ["'", "'"]
  ];
  for (const [open, close] of pairs) {
    if (text.length > 2 && text.startsWith(open) && text.endsWith(close)) {
      const inner = text.slice(open.length, text.length - close.length);
      if (!inner.includes(close)) return inner.trim();
    }
  }
  return text;
}

/**
 * @returns {{reply: string, usage: {inputTokens: number, outputTokens: number}, model: string}}
 */
export async function generateReply({ developer, user }) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), config.openAI.timeoutMs);

  let response;
  try {
    response = await fetch(`${config.openAI.baseURL}/responses`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${config.openAI.apiKey}`
      },
      signal: controller.signal,
      body: JSON.stringify({
        model: config.openAI.model,
        max_output_tokens: config.openAI.maxOutputTokens,
        temperature: 0.7,
        // No server-side conversation state: each reply is independent, and
        // storing message content upstream is exactly what the privacy rules
        // here rule out.
        store: false,
        input: [
          { role: 'developer', content: developer },
          { role: 'user', content: user }
        ]
      })
    });
  } catch (error) {
    clearTimeout(timer);
    if (error?.name === 'AbortError') {
      throw new UpstreamError(ErrorCode.upstreamTimeout, 504);
    }
    throw new UpstreamError(ErrorCode.upstreamUnavailable, 502, error?.message);
  }
  clearTimeout(timer);

  if (!response.ok) {
    // The upstream body may quote the prompt back. It is read for the status
    // mapping below and never returned to the client or written to a log.
    let upstreamMessage;
    try {
      const body = await response.json();
      upstreamMessage = body?.error?.message;
    } catch {
      upstreamMessage = undefined;
    }
    const code =
      response.status === 429 ? ErrorCode.rateLimited : ErrorCode.upstreamUnavailable;
    throw new UpstreamError(code, response.status === 429 ? 429 : 502, upstreamMessage);
  }

  const payload = await response.json();
  const text = unwrapQuotes(extractText(payload));

  if (!text) {
    // Most commonly the output budget ran out before any text was emitted.
    throw new UpstreamError(ErrorCode.emptyCompletion, 502, payload?.status);
  }

  return {
    reply: text,
    model: payload?.model ?? config.openAI.model,
    usage: {
      inputTokens: payload?.usage?.input_tokens ?? 0,
      outputTokens: payload?.usage?.output_tokens ?? 0
    }
  };
}

export const __test__ = { extractText, unwrapQuotes };
