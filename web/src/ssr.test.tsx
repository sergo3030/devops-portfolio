// @vitest-environment node
import { renderToString } from 'react-dom/server';
import { App } from './App';
import { loadSnapshot } from './content';
import { withCaseStudy } from './fixtures';

describe('server rendering', () => {
  it('renders without any browser globals, so the site can be pre-rendered later', () => {
    expect(typeof window).toBe('undefined');
    const html = renderToString(<App content={loadSnapshot()} />);
    expect(html).toContain('<h1');
    for (const heading of ['Experience', 'Skills', 'Languages']) {
      expect(html).toContain(heading);
    }
    expect(html).toContain('Mar 2024');
  });

  it('renders case studies on a server too', () => {
    const html = renderToString(<App content={withCaseStudy} />);
    expect(html).toContain('A cluster upgrade');
  });
});
