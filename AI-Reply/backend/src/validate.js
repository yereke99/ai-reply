import { config } from './config.js';

/** Errors the client is allowed to see, as stable codes it can localize. */
export const ErrorCode = {
  invalidRequest: 'invalid_request',
  messageEmpty: 'message_empty',
  messageTooLong: 'message_too_long',
  unauthorized: 'unauthorized',
  rateLimited: 'rate_limited',
  upstreamUnavailable: 'upstream_unavailable',
  upstreamTimeout: 'upstream_timeout',
  emptyCompletion: 'empty_completion',
  internal: 'internal'
};

/**
 * Counts Unicode SCALAR VALUES, matching Swift's `String.count` closely enough
 * for the 300-character rule to mean the same thing on both sides.
 * `String.length` in JS counts UTF-16 code units, which would let an emoji or a
 * surrogate pair count twice and reject a message the app accepted.
 */
export function characterCount(value) {
  return [...value].length;
}

function clampString(value, max) {
  if (typeof value !== 'string') return '';
  const trimmed = value.trim();
  if (characterCount(trimmed) <= max) return trimmed;
  return [...trimmed].slice(0, max).join('');
}

const TONES = new Set(['natural', 'friendly', 'professional', 'formal', 'short']);
const LENGTHS = new Set(['short', 'medium']);
const HOURS_BEHAVIOURS = new Set(['ignore', 'mention_when_relevant', 'always_mention']);
const EMOJI_POLICIES = new Set(['allowed', 'minimal', 'none']);

/**
 * Normalizes the business block a client may send at either level.
 *
 * Everything is clamped and capped here rather than trusted, for the same
 * reason the message limit is enforced server-side: a client can always be
 * modified, and an unbounded rule list is an unbounded prompt.
 */
function normalizeBusiness(raw) {
  const source = raw && typeof raw === 'object' ? raw : {};
  const rules = Array.isArray(source.rules) ? source.rules : [];
  return {
    offering: clampString(source.offering, config.limits.businessOfferingCharacters),
    summary: clampString(source.summary, config.limits.businessSummaryCharacters),
    rules: rules
      .map((rule) => clampString(rule, config.limits.businessRuleCharacters))
      .filter((rule) => rule.length > 0)
      .slice(0, config.limits.businessRules)
  };
}

/**
 * Normalizes an incoming request into a shape the prompt builder can trust.
 *
 * Everything here is defensive on purpose. The client-side 300-character check
 * is a courtesy to the user; this one is the actual rule, because a client can
 * always be modified.
 *
 * @returns {{ok: true, value: object} | {ok: false, code: string, detail?: object}}
 */
export function normalizeReplyRequest(body) {
  if (!body || typeof body !== 'object') {
    return { ok: false, code: ErrorCode.invalidRequest };
  }

  const rawMessage = typeof body.message === 'string' ? body.message.trim() : '';
  if (!rawMessage) {
    return { ok: false, code: ErrorCode.messageEmpty };
  }

  const length = characterCount(rawMessage);
  if (length > config.limits.messageCharacters) {
    return {
      ok: false,
      code: ErrorCode.messageTooLong,
      detail: { limit: config.limits.messageCharacters, actual: length }
    };
  }

  const templateId =
    typeof body.template_id === 'string' && body.template_id.length <= 64
      ? body.template_id
      : 'custom';

  const keyboardLanguage = ['en', 'ru', 'kk'].includes(body.keyboard_language)
    ? body.keyboard_language
    : 'en';

  const profileIn = body.profile && typeof body.profile === 'object' ? body.profile : {};
  const templateIn = body.template && typeof body.template === 'object' ? body.template : {};
  const businessIn =
    body.business_context && typeof body.business_context === 'object'
      ? body.business_context
      : {};

  const profile = {
    description: clampString(profileIn.description, config.limits.profileCharacters),
    role: clampString(profileIn.role, config.limits.profileRoleCharacters),
    preferredTone: TONES.has(profileIn.preferred_tone) ? profileIn.preferred_tone : 'natural',
    business: normalizeBusiness(profileIn.business)
  };

  const template = {
    name: clampString(templateIn.name, config.limits.templateNameCharacters) || 'Custom',
    relationship: clampString(templateIn.relationship, 40),
    tone: TONES.has(templateIn.tone) ? templateIn.tone : profile.preferredTone,
    instructions: clampString(
      templateIn.instructions,
      config.limits.templateInstructionCharacters
    ),
    replyLength: LENGTHS.has(templateIn.reply_length) ? templateIn.reply_length : 'short',
    emojiPolicy: EMOJI_POLICIES.has(templateIn.emoji_policy) ? templateIn.emoji_policy : 'minimal',
    business: normalizeBusiness(templateIn.business),
    workingHoursBehaviour: HOURS_BEHAVIOURS.has(templateIn.working_hours_behaviour)
      ? templateIn.working_hours_behaviour
      : 'mention_when_relevant'
  };

  const businessEnabled = businessIn.enabled === true;
  const business = {
    enabled: businessEnabled,
    isWithinWorkingHours: businessEnabled ? businessIn.is_within_working_hours === true : null,
    currentLocalTime: clampString(businessIn.current_local_time, 32),
    nextWorkingPeriod: clampString(businessIn.next_working_period, 80),
    weeklySchedule: clampString(businessIn.weekly_schedule, 200)
  };

  return {
    ok: true,
    value: { message: rawMessage, templateId, keyboardLanguage, profile, template, business }
  };
}
