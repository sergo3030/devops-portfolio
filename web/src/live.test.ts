import { sampleContent } from './fixtures';
import { fetchLive } from './live';

const json = (body: unknown, status = 200) =>
  Promise.resolve(new Response(JSON.stringify(body), { status }));

/** A fake `fetch` that answers by path. Any path not listed fails like a dead network. */
function fakeFetch(routes: Record<string, () => Promise<Response>>): typeof fetch {
  return (input) => {
    const path = new URL(String(input), 'http://api.test').pathname;
    const route = routes[path];
    return route ? route() : Promise.reject(new TypeError('network down'));
  };
}

const hanging: typeof fetch = (_input, init) =>
  new Promise((_resolve, reject) => {
    init?.signal?.addEventListener('abort', () => {
      reject(new DOMException('aborted', 'AbortError'));
    });
  });

afterEach(() => {
  vi.useRealTimers();
});

describe('fetchLive', () => {
  it('returns the content and the version', async () => {
    const fetchImpl = fakeFetch({
      '/content': () => json(sampleContent),
      '/health': () => json({ status: 'ok', version: '1.2.3' }),
    });
    await expect(fetchLive('http://api.test', { fetchImpl })).resolves.toEqual({
      content: sampleContent,
      version: '1.2.3',
    });
  });

  it('still returns the content when /health fails or reports an odd version', async () => {
    for (const health of [
      () => Promise.reject(new TypeError('network down')),
      () => json({ version: '<script>' }),
      () => json({}, 500),
    ]) {
      const fetchImpl = fakeFetch({ '/content': () => json(sampleContent), '/health': health });
      await expect(fetchLive('http://api.test', { fetchImpl })).resolves.toEqual({
        content: sampleContent,
      });
    }
  });

  it.each([
    ['a server error', () => json({ detail: 'boom' }, 500)],
    ['a network error', () => Promise.reject(new TypeError('network down'))],
    ['text that is not JSON', () => Promise.resolve(new Response('<html>', { status: 200 }))],
    ['data of the wrong shape', () => json({ version: 1, profile: 'nope' })],
  ])('rejects %s from /content', async (_label, content) => {
    const fetchImpl = fakeFetch({ '/content': content, '/health': () => json({ version: '1' }) });
    await expect(fetchLive('http://api.test', { fetchImpl })).rejects.toThrow();
  });

  it('gives up when the API is too slow', async () => {
    vi.useFakeTimers();
    const result = expect(
      fetchLive('http://api.test', { fetchImpl: hanging, timeoutMs: 5000 }),
    ).rejects.toThrow();
    await vi.advanceTimersByTimeAsync(5000);
    await result;
  });

  it('stops when the caller aborts, for example when the page is closed', async () => {
    const controller = new AbortController();
    const result = expect(
      fetchLive('http://api.test', { fetchImpl: hanging, signal: controller.signal }),
    ).rejects.toThrow();
    controller.abort();
    await result;
  });
});
