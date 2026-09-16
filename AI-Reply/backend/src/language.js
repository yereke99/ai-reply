/**
 * Cheap script heuristic for the `detected_language` field.
 *
 * Advisory only - the model decides what language to answer in, and this just
 * reports what came out. It is not used to steer generation, so being wrong on
 * a three-word reply costs nothing.
 */

const KAZAKH_SPECIFIC = /[әғқңөұүһіӘҒҚҢӨҰҮҺІ]/;
const CYRILLIC = /[Ѐ-ӿ]/g;
const LATIN = /[A-Za-z]/g;

export function detectLanguage(text) {
  if (!text) return null;
  if (KAZAKH_SPECIFIC.test(text)) return 'kk';
  const cyrillic = (text.match(CYRILLIC) ?? []).length;
  const latin = (text.match(LATIN) ?? []).length;
  if (cyrillic === 0 && latin === 0) return null;
  return cyrillic > latin ? 'ru' : 'en';
}
