/**
 * Normalize asset URLs (sprite images, file uploads, etc.) so they resolve
 * correctly under both the dev server (BASE='/') and the per-instance
 * Static Preview path (BASE='/preview/<activity_type_id>/<activity_id>/').
 */

import { BASE_PREFIX } from './api-base';

export function resolveAssetUrl(src: string): string {
  if (!src) return src;
  if (/^(https?:|data:|blob:)/i.test(src)) return src;
  if (BASE_PREFIX && src.startsWith(BASE_PREFIX + '/')) return src;
  if (src.startsWith('/')) return BASE_PREFIX + src;
  return src;
}
