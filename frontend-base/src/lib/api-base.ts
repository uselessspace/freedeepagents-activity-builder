/**
 * BASE_URL resolution shared by all FreeDeepAgents frontend templates.
 *
 * Static Preview can be served under `/preview/<aid>/<iid>/`, the FDA
 * developer mirror `/dev/preview/<aid>/<iid>/`, or the Go developer proxy
 * `/api/v1/developer/activity-types/<aid>/activities/<iid>/preview/`.
 * Preserve the current preview prefix so `/api` calls stay in the same route.
 */

function isGoDeveloperPreviewMount(parts: string[], previewIdx: number): boolean {
  return (
    previewIdx >= 7 &&
    parts[0] === 'api' &&
    parts[1] === 'v1' &&
    parts[2] === 'developer' &&
    parts[3] === 'activity-types' &&
    parts[5] === 'activities' &&
    parts[7] === 'preview'
  );
}

function resolveBasePrefix(): string {
  const fallback = import.meta.env.BASE_URL.replace(/\/+$/, '') || '';
  if (typeof window === 'undefined') return fallback;

  const parts = window.location.pathname.split('/').filter(Boolean);
  const previewIdx = parts.indexOf('preview');
  if (previewIdx >= 0 && isGoDeveloperPreviewMount(parts, previewIdx)) {
    return `/${parts.slice(0, previewIdx + 1).join('/')}`;
  }
  if (previewIdx >= 0 && parts.length >= previewIdx + 3) {
    return `/${parts.slice(0, previewIdx + 3).join('/')}`;
  }
  return fallback;
}

export const BASE_PREFIX: string = resolveBasePrefix();

export const BASE: string = BASE_PREFIX + '/api';

export function apiUrl(path: string): string {
  return BASE + (path.startsWith('/') ? path : '/' + path);
}
