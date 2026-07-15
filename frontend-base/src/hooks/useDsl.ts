import { useCallback, useEffect, useState } from 'react';

import { api, openDslStream } from '../lib/api-client';
import { mockDsl } from '../lib/mock-dsl';
import type { AppDsl, PreviewNavigationEvent } from '../lib/types';

export function useDsl() {
  const [data, setData] = useState<AppDsl | null>(null);
  const [error, setError] = useState<Error | null>(null);
  const [loading, setLoading] = useState(true);
  const [navigation, setNavigation] = useState<PreviewNavigationEvent | null>(null);

  const refresh = useCallback(async () => {
    try {
      setError(null);
      const next = await api.fetchDsl();
      setData(next);
    } catch (err) {
      if (import.meta.hot) {
        setData(mockDsl);
        setError(null);
        return;
      }
      setError(err as Error);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (import.meta.hot) return;
    const source = openDslStream(
      (next) => setData(next),
      () => {
        void refresh();
      },
      (event) => setNavigation((current) => (current?.event_id === event.event_id ? current : event)),
    );
    return () => source.close();
  }, [refresh]);

  return { data, error, loading, refresh, navigation };
}
