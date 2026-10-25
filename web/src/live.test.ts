import { sampleContent } from './fixtures';
import { fetchLive, TIMEOUT_MS } from './live';

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

  it('waits long enough for a cold start of 5 s, and gives up at 8 s', async () => {
    expect(TIMEOUT_MS).toBe(8000);
    vi.useFakeTimers();
    const slow: typeof fetch = (input, init) =>
      new Promise((resolve, reject) => {
        init?.signal?.addEventListener('abort', () => {
          reject(new DOMException('aborted', 'AbortError'));
        });
        const delay = String(input).endsWith('/content') ? 5000 : 100;
        setTimeout(() => {
          resolve(
            String(input).endsWith('/content')
              ? new Response(JSON.stringify(sampleContent))
              : new Response(JSON.stringify({ status: 'ok', version: '1.2.3' })),
          );
        }, delay);
      });
    const result = fetchLive('http://api.test', { fetchImpl: slow });
    await vi.advanceTimersByTimeAsync(5100);
    await expect(result).resolves.toEqual({ content: sampleContent, version: '1.2.3' });

    const never = expect(fetchLive('http://api.test', { fetchImpl: hanging })).rejects.toThrow();
    await vi.advanceTimersByTimeAsync(7999);
    await vi.advanceTimersByTimeAsync(1);
    await never;
  });

  it('asks for /health only after /content has answered', async () => {
    const order: string[] = [];
    let releaseContent: () => void = () => undefined;
    const fetchImpl: typeof fetch = (input) => {
      const path = new URL(String(input), 'http://api.test').pathname;
      order.push(`start ${path}`);
      if (path === '/content') {
        return new Promise((resolve) => {
          releaseContent = () => {
            order.push('end /content');
            resolve(new Response(JSON.stringify(sampleContent)));
          };
        });
      }
      return json({ status: 'ok', version: '1.2.3' });
    };
    const result = fetchLive('http://api.test', { fetchImpl });
    await Promise.resolve();
    expect(order).toEqual(['start /content']);
    releaseContent();
    await result;
    expect(order).toEqual(['start /content', 'end /content', 'start /health']);
  });

  it('keeps the content when the deadline passes while /health is still running', async () => {
    vi.useFakeTimers();
    const fetchImpl: typeof fetch = (input, init) =>
      String(input).endsWith('/content') ? json(sampleContent) : hanging(input, init);
    const result = fetchLive('http://api.test', { fetchImpl, timeoutMs: 1000 });
    await vi.advanceTimersByTimeAsync(1000);
    await expect(result).resolves.toEqual({ content: sampleContent });
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
