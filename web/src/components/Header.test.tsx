import { render, screen } from '@testing-library/react';
import { Header, moduleGroups } from './Header';

const profile = { name: 'Test Person', title: 'DevOps Engineer', country: 'Nowhere' };
const links = [{ label: 'Code', url: 'https://example.com/code' }];
const group = (category: string, items: string[]) => ({ category, items });

describe('moduleGroups', () => {
  it('takes the first six groups that have more than one skill', () => {
    const groups = [
      group('Alone', ['One']),
      ...Array.from({ length: 8 }, (_, index) => group(`Group ${String(index)}`, ['A', 'B'])),
    ];
    expect(moduleGroups(groups).map((item) => item.category)).toEqual([
      'Group 0',
      'Group 1',
      'Group 2',
      'Group 3',
      'Group 4',
      'Group 5',
    ]);
  });
});

describe('Header', () => {
  it('draws skill modules beside the device, hidden from assistive technology', () => {
    const { container } = render(
      <Header
        profile={profile}
        links={links}
        skills={[group('Containers', ['Kubernetes', 'Docker']), group('Logs', ['Loki', 'Grafana'])]}
      />,
    );
    const hidden = container.querySelectorAll('[aria-hidden="true"] [data-text]');
    expect([...hidden].map((element) => element.getAttribute('data-text'))).toEqual([
      'Containers',
      'Kubernetes',
      'Docker',
      'Logs',
      'Loki',
      'Grafana',
    ]);
  });

  it('keeps the words of the modules out of the page text, so a skill is found once', () => {
    render(
      <Header profile={profile} links={links} skills={[group('Containers', ['Docker', 'Helm'])]} />,
    );
    expect(screen.queryByText('Docker')).not.toBeInTheDocument();
    expect(screen.queryByText('Containers')).not.toBeInTheDocument();
  });

  it('has no side modules without skills', () => {
    const { container } = render(<Header profile={profile} links={links} />);
    expect(container.querySelectorAll('[data-text]')).toHaveLength(0);
    expect(screen.getByRole('heading', { level: 1, name: 'Test Person' })).toBeInTheDocument();
  });
});
