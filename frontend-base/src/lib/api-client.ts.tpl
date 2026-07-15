/**
 * Static Preview API client.
 *
 * Production runtime exposes:
 *   - GET /preview/<activity_type_id>/<activity_id>/api/dsl.json
 *   - GET /preview/<activity_type_id>/<activity_id>/api/dsl/stream
 *
 * Because the built app is served below `/preview/<activity_type_id>/<activity_id>/`, relative
 * requests to `/api/...` are constructed through `apiUrl()`.
 */

import { apiUrl } from './api-base';
import { request } from './http';
import type { AppDsl, PreviewNavigationEvent } from './types';

export const api = {
  fetchDsl: (): Promise<AppDsl> => request('/dsl.json'),
};

export function openDslStream(
  onDsl: (dsl: AppDsl) => void,
  onError?: (event: Event) => void,
  onPreviewNavigate?: (event: PreviewNavigationEvent) => void,
): EventSource {
  const source = new EventSource(apiUrl('/dsl/stream'));
  source.onmessage = (event) => {
    onDsl(JSON.parse(event.data) as AppDsl);
  };
  source.addEventListener('preview_navigate', (event) => {
    if (!onPreviewNavigate) return;
    try {
      const value = JSON.parse(event.data) as unknown;
      if (
        typeof value === 'object' &&
        value !== null &&
        typeof (value as Record<string, unknown>).event_id === 'string' &&
        typeof (value as Record<string, unknown>).turn_id === 'string'
      ) {
        onPreviewNavigate(value as PreviewNavigationEvent);
      }
    } catch {
      // A malformed optional UX event must not interrupt durable DSL updates.
    }
  });
  if (onError) source.onerror = onError;
  return source;
}
