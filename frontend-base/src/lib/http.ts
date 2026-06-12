/**
 * Shared HTTP request helper for FreeDeepAgents frontend templates.
 *
 * Source of truth: <package>/frontend-base/src/lib/http.ts
 * Do NOT edit copies in derived templates — change here, re-derive (or
 * cherry-pick the file directly).
 */

import { BASE } from './api-base';

export class JsonError extends Error {
  constructor(public status: number, public method: string, public path: string, public detail: string) {
    super(`API ${method} ${path} → ${status}${detail ? ': ' + detail : ''}`);
    this.name = 'JsonError';
  }
}

export async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(BASE + path, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
  });
  if (!res.ok) {
    let detail = '';
    try {
      const body = await res.json();
      detail = typeof body?.error === 'string' ? body.error : '';
    } catch {
      // body wasn't JSON; that's fine, we'll just have an empty detail
    }
    throw new JsonError(res.status, init?.method ?? 'GET', path, detail);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}
