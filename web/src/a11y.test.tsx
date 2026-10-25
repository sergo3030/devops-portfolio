import { render } from '@testing-library/react';
import axe from 'axe-core';
import { App } from './App';
import { loadSnapshot } from './content';
import { withAbout, withCaseStudy } from './fixtures';

async function violations(container: HTMLElement): Promise<string[]> {
  // Colour contrast needs a real browser; jsdom has no layout or computed colours.
  const results = await axe.run(container, { rules: { 'color-contrast': { enabled: false } } });
  return results.violations.map((violation) => violation.id);
}

describe('accessibility baseline', () => {
  it('has no automatically detectable violations in the real content', async () => {
    const { container } = render(<App content={loadSnapshot()} />);
    expect(await violations(container)).toEqual([]);
  });

  it('has none with a case study published either', async () => {
    const { container } = render(<App content={withCaseStudy} />);
    expect(await violations(container)).toEqual([]);
  });

  it('has none with the About section published', async () => {
    const { container } = render(<App content={{ ...withCaseStudy, about: withAbout.about }} />);
    expect(await violations(container)).toEqual([]);
  });

  it('has none with the data status line, live or offline', async () => {
    for (const dataSource of [{ kind: 'live', version: '1.2.3' }, { kind: 'offline' }] as const) {
      const { container, unmount } = render(
        <App content={withCaseStudy} dataSource={dataSource} />,
      );
      expect(await violations(container)).toEqual([]);
      unmount();
    }
  });
});
