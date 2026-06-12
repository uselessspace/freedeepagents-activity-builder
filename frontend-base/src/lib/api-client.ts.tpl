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
import type { AppDsl } from './types';

export const api = {
  fetchDsl: (): Promise<AppDsl> => request('/dsl.json'),
};

export function openDslStream(onDsl: (dsl: AppDsl) => void, onError?: (event: Event) => void): EventSource {
  const source = new EventSource(apiUrl('/dsl/stream'));
  source.onmessage = (event) => {
    onDsl(JSON.parse(event.data) as AppDsl);
  };
  if (onError) source.onerror = onError;
  return source;
}
