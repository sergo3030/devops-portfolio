// @vitest-environment node
import { renderToString } from 'react-dom/server';
import { App } from './App';
import { loadSnapshot } from './content';

describe('server rendering', () => {
  it('renders without any browser globals, so the site can be pre-rendered later', () => {
    expect(typeof window).toBe('undefined');
    const html = renderToString(<App content={loadSnapshot()} />);
    expect(html).toContain('<h1');
  });
});
