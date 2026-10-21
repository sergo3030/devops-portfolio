import { useEffect, useState } from 'react';
import type { Content } from './generated/content';
import { isContent } from './guard';

export const TIMEOUT_MS = 5000;

/** What the status line says: nothing, data from the API, or a saved copy because the API failed. */
export type DataSource =
  { kind: 'none' } | { kind: 'live'; version?: string } | { kind: 'offline' };

export type LiveResult = { content: Content; version?: string };

const VERSION = /^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$/;

async function getJson(
  url: string,
  signal: AbortSignal,
  fetchImpl: typeof fetch,
): Promise<unknown> {
  // `no-cache` makes the browser ask the API every time. Without it, `/content` (which the API
  // marks cacheable for five minutes) could be answered from the cache while the API is down, and
  // the page would say "Live from API" about an API that is not there.
  const response = await fetchImpl(url, {
    signal,
    cache: 'no-cache',
    headers: { Accept: 'application/json' },
  });
  if (!response.ok) throw new Error(`${url} answered ${response.status}`);
  return response.json();
}

/**
 * Reads `/content` and `/health` from the API. Both share one deadline. A bad `/content` (wrong
 * status, not JSON, wrong shape, too slow) rejects. A bad `/health` only costs the version label.
 * The caller's signal cancels both requests, for example when the page is closed.
 */
export async function fetchLive(
  base: string,
  options: { timeoutMs?: number; signal?: AbortSignal; fetchImpl?: typeof fetch } = {},
): Promise<LiveResult> {
  const { timeoutMs = TIMEOUT_MS, signal, fetchImpl = fetch } = options;
  const controller = new AbortController();
  const abort = () => {
    controller.abort();
  };
  signal?.addEventListener('abort', abort);
  const timer = setTimeout(abort, timeoutMs);
  try {
    const health = getJson(`${base}/health`, controller.signal, fetchImpl)
      .then((body) =>
        typeof body === 'object' &&
        body !== null &&
        'version' in body &&
        typeof body.version === 'string' &&
        VERSION.test(body.version)
          ? body.version
          : undefined,
      )
      .catch(() => undefined);
    const body = await getJson(`${base}/content`, controller.signal, fetchImpl);
    if (!isContent(body)) throw new Error('The API content does not match the content contract.');
    const version = await health;
    return version === undefined ? { content: body } : { content: body, version };
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener('abort', abort);
  }
}

/**
 * Shows the saved copy at once, then swaps in the API's content if it answers in time. With no
 * API configured nothing is fetched and no status is shown.
 */
export function useLiveContent(
  snapshot: Content,
  base: string | undefined,
): { content: Content; source: DataSource } {
  const [state, setState] = useState<{ content: Content; source: DataSource }>({
    content: snapshot,
    source: { kind: 'none' },
  });

  useEffect(() => {
    if (!base) return;
    const controller = new AbortController();
    fetchLive(base, { signal: controller.signal })
      .then((live) => {
        setState({
          content: live.content,
          source:
            live.version === undefined ? { kind: 'live' } : { kind: 'live', version: live.version },
        });
      })
      .catch(() => {
        if (!controller.signal.aborted)
          setState({ content: snapshot, source: { kind: 'offline' } });
      });
    return () => {
      controller.abort();
    };
  }, [base, snapshot]);

  return state;
}
