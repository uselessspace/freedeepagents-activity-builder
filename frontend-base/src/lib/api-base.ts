/**
 * BASE_URL resolution shared by all FreeDeepAgents frontend templates.
 *
 * Static Preview serves the built SPA under `/preview/<activity_type_id>/<activity_id>/`.
 * `vite.config.ts` uses `base: './'`, so `import.meta.env.BASE_URL` stays
 * relative and `/api` calls resolve under that preview route.
 */

export const BASE_PREFIX: string = (import.meta.env.BASE_URL.replace(/\/+$/, '') || '');

export const BASE: string = BASE_PREFIX + '/api';

export function apiUrl(path: string): string {
  return BASE + (path.startsWith('/') ? path : '/' + path);
}
