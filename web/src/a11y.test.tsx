import { render } from '@testing-library/react';
import axe from 'axe-core';
import { App } from './App';
import { loadSnapshot } from './content';

describe('accessibility baseline', () => {
  it('has no automatically detectable violations (colour contrast needs a real browser)', async () => {
    const { container } = render(<App content={loadSnapshot()} />);
    const results = await axe.run(container, { rules: { 'color-contrast': { enabled: false } } });
    expect(results.violations.map((violation) => violation.id)).toEqual([]);
  });
});
