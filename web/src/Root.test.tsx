import { render, screen } from '@testing-library/react';
import { ErrorBoundary } from './components/ErrorBoundary';
import { sampleContent } from './fixtures';
import { Root } from './Root';

const livePerson = { ...sampleContent, profile: { ...sampleContent.profile, name: 'Live Person' } };

function stubApi(content: () => Promise<Response>, health?: () => Promise<Response>) {
  const fetchStub = vi.fn((input: RequestInfo | URL) =>
    String(input).endsWith('/health')
      ? (health?.() ?? Promise.reject(new TypeError('no health')))
      : content(),
  );
  vi.stubGlobal('fetch', fetchStub);
  return fetchStub;
}

const ok = (body: unknown) => () => Promise.resolve(new Response(JSON.stringify(body)));

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('Root', () => {
  it('shows the saved copy and calls nothing when no API is configured', () => {
    const fetchStub = stubApi(ok(livePerson));
    render(<Root snapshot={sampleContent} apiBase={undefined} />);
    expect(screen.getByRole('heading', { level: 1, name: 'Test Person' })).toBeInTheDocument();
    expect(fetchStub).not.toHaveBeenCalled();
    expect(screen.queryByText(/API/)).not.toBeInTheDocument();
  });

  it('shows the saved copy first, then the live data and its version', async () => {
    stubApi(ok(livePerson), ok({ status: 'ok', version: '1.2.3' }));
    render(<Root snapshot={sampleContent} apiBase="http://api.test" />);
    expect(screen.getByRole('heading', { level: 1, name: 'Test Person' })).toBeInTheDocument();

    expect(
      await screen.findByRole('heading', { level: 1, name: 'Live Person' }),
    ).toBeInTheDocument();
    expect(screen.getByText('Live from API · version 1.2.3')).toBeInTheDocument();
  });

  it('keeps the saved copy and says the API is offline when it fails', async () => {
    stubApi(() => Promise.reject(new TypeError('network down')));
    render(<Root snapshot={sampleContent} apiBase="http://api.test" />);
    expect(await screen.findByText('API offline: showing the saved copy')).toBeInTheDocument();
    expect(screen.getByRole('heading', { level: 1, name: 'Test Person' })).toBeInTheDocument();
  });

  it('does not show data of the wrong shape', async () => {
    stubApi(ok({ ...livePerson, links: [{ label: 'x', url: 'javascript:alert(1)' }] }));
    render(<Root snapshot={sampleContent} apiBase="http://api.test" />);
    expect(await screen.findByText('API offline: showing the saved copy')).toBeInTheDocument();
    expect(screen.queryByText('Live Person')).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'x' })).not.toBeInTheDocument();
  });
});

describe('ErrorBoundary', () => {
  it('shows the fallback when a child throws', () => {
    const quiet = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const Broken = (): never => {
      throw new Error('broken');
    };
    render(
      <ErrorBoundary fallback={<p>fallback</p>}>
        <Broken />
      </ErrorBoundary>,
    );
    expect(screen.getByText('fallback')).toBeInTheDocument();
    quiet.mockRestore();
  });
});
