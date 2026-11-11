import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { App } from './App';
import { emptyContent, sampleContent, withAbout, withCaseStudy } from './fixtures';

describe('App', () => {
  it('shows the name as the page heading, then the title, country and summary', () => {
    render(<App content={sampleContent} />);
    expect(screen.getByRole('heading', { level: 1, name: 'Test Person' })).toBeInTheDocument();
    expect(screen.getByText('DevOps Engineer')).toBeInTheDocument();
    expect(screen.getByText('Nowhere')).toBeInTheDocument();
    expect(screen.getByText('Builds platforms.')).toBeInTheDocument();
  });

  it('leaves out the summary when it is not published', () => {
    render(<App content={{ ...sampleContent, profile: { name: 'Test Person' } }} />);
    expect(screen.queryByText('Builds platforms.')).not.toBeInTheDocument();
  });

  it('opens profile links in a new tab without handing over the opener', () => {
    render(<App content={sampleContent} />);
    const link = screen.getByRole('link', { name: 'Code' });
    expect(link).toHaveAttribute('href', 'https://example.com/code');
    expect(link).toHaveAttribute('target', '_blank');
    expect(link).toHaveAttribute('rel', 'noopener noreferrer');
  });

  it('shows the experience newest first with readable dates', () => {
    render(<App content={sampleContent} />);
    const jobs = within(screen.getByRole('region', { name: 'Experience' })).getAllByRole(
      'heading',
      {
        level: 3,
      },
    );
    expect(jobs.map((job) => job.textContent)).toEqual(['Lead, New Co', 'Engineer, Old Co']);
    expect(screen.getByText('Mar 2024 – present')).toBeInTheDocument();
  });

  it('leaves out sections that have nothing to show, including case studies', () => {
    render(<App content={emptyContent} />);
    expect(screen.getByRole('heading', { level: 1 })).toBeInTheDocument();
    for (const name of ['Experience', 'Skills', 'Case studies', 'Languages']) {
      expect(screen.queryByRole('region', { name })).not.toBeInTheDocument();
    }
  });

  it('shows case studies once one is published', () => {
    render(<App content={withCaseStudy} />);
    const region = screen.getByRole('region', { name: 'Case studies' });
    expect(
      within(region).getByRole('heading', { level: 3, name: 'A cluster upgrade' }),
    ).toBeInTheDocument();
    expect(within(region).getByText('It worked.')).toBeInTheDocument();
  });

  it('keeps the About section off the portfolio view and links to it from the header', () => {
    render(<App content={withAbout} />);
    expect(screen.queryByRole('region', { name: 'About this project' })).not.toBeInTheDocument();
    expect(screen.queryByRole('group', { name: 'Scenario' })).not.toBeInTheDocument();
    expect(screen.getByRole('region', { name: 'Experience' })).toBeInTheDocument();
    const pages = screen.getByRole('navigation', { name: 'Pages' });
    const portfolio = within(pages).getByRole('link', { name: 'Portfolio' });
    const about = within(pages).getByRole('link', { name: 'About this project' });
    expect(portfolio).toHaveAttribute('aria-current', 'page');
    expect(about).toHaveAttribute('href', '#about');
    expect(about).not.toHaveAttribute('aria-current');
    expect(about).not.toHaveAttribute('target');
  });

  it('shows the About page with its own anchor, and none of the portfolio sections', () => {
    render(<App content={withAbout} page="about" />);
    const region = screen.getByRole('region', { name: 'About this project' });
    expect(region).toHaveAttribute('id', 'about');
    expect(
      within(region)
        .getAllByRole('heading', { level: 3 })
        .map((h) => h.textContent),
    ).toEqual(['Why', 'How']);
    expect(within(region).getByText('Because it is a good example.')).toBeInTheDocument();
    expect(within(region).getByText('With checks.')).toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'Experience' })).not.toBeInTheDocument();
    expect(screen.getByRole('heading', { level: 1, name: 'Test Person' })).toBeInTheDocument();
    const pages = screen.getByRole('navigation', { name: 'Pages' });
    expect(within(pages).getByRole('link', { name: 'About this project' })).toHaveAttribute(
      'aria-current',
      'page',
    );
    expect(within(pages).getByRole('link', { name: 'Portfolio' })).not.toHaveAttribute(
      'aria-current',
    );
  });

  it('shows the first About section as the summary, with the diagram before the cards', () => {
    render(<App content={withAbout} page="about" />);
    const region = screen.getByRole('region', { name: 'About this project' });
    expect(within(region).getByRole('heading', { level: 3, name: 'Why' })).toBeInTheDocument();
    expect(within(region).getByRole('group', { name: 'Scenario' })).toBeInTheDocument();
    expect(within(region).getByRole('button', { name: 'Next' })).toBeInTheDocument();
    expect(within(region).getByRole('heading', { level: 3, name: 'How' })).toBeInTheDocument();
  });

  it('names the tab after the page, and moves focus to the content when the page changes', () => {
    const { container, rerender } = render(<App content={withAbout} />);
    const base = document.title;
    rerender(<App content={withAbout} page="about" />);
    expect(document.title).toBe(`About this project | ${base}`);
    expect(container.querySelector('[tabindex="-1"]')).toHaveFocus();
    rerender(<App content={withAbout} />);
    expect(document.title).toBe(base);
  });

  it('shows no diagram when there is no About section', () => {
    render(<App content={sampleContent} />);
    expect(screen.queryByRole('group', { name: 'Scenario' })).not.toBeInTheDocument();
  });

  it('shows no About page and no navigation when none is published', () => {
    for (const about of [undefined, null, { title: 'About this project', sections: [] }]) {
      const { unmount } = render(<App content={{ ...sampleContent, about }} page="about" />);
      expect(screen.queryByRole('region', { name: 'About this project' })).not.toBeInTheDocument();
      expect(screen.queryByRole('navigation', { name: 'Pages' })).not.toBeInTheDocument();
      expect(screen.getByRole('region', { name: 'Experience' })).toBeInTheDocument();
      unmount();
    }
  });

  it('names the About page with a default when the title is not published', () => {
    render(
      <App
        content={{ ...withAbout, about: { sections: withAbout.about!.sections } }}
        page="about"
      />,
    );
    expect(screen.getByRole('region', { name: 'About this project' })).toBeInTheDocument();
  });

  it('lists the languages', () => {
    render(<App content={sampleContent} />);
    const region = screen.getByRole('region', { name: 'Languages' });
    expect(
      within(region)
        .getAllByRole('listitem')
        .map((item) => item.textContent),
    ).toEqual(['English', 'Hebrew']);
  });
});

describe('skills filter', () => {
  it('narrows the skills as the visitor types and says how many are shown', async () => {
    const user = userEvent.setup();
    render(<App content={sampleContent} />);
    expect(screen.getByRole('status')).toHaveTextContent('4 skills shown');

    await user.type(screen.getByRole('searchbox', { name: 'Filter skills' }), 'graf');
    expect(screen.getByText('Grafana')).toBeInTheDocument();
    expect(screen.queryByText('Docker')).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Containers' })).not.toBeInTheDocument();
    expect(screen.getByRole('status')).toHaveTextContent('1 skill shown');
  });

  it('leaves an empty slot, without text, for every skill the filter hides', async () => {
    const user = userEvent.setup();
    const { container } = render(<App content={sampleContent} />);
    expect(container.querySelectorAll('li[aria-hidden="true"]')).toHaveLength(0);

    await user.type(screen.getByRole('searchbox', { name: 'Filter skills' }), 'graf');
    const slots = container.querySelectorAll('li[aria-hidden="true"]');
    expect(slots).toHaveLength(1);
    expect(slots[0]).toBeEmptyDOMElement();
    expect(screen.queryByText('Prometheus')).not.toBeInTheDocument();
  });

  it('says so when nothing matches, and recovers when the box is cleared', async () => {
    const user = userEvent.setup();
    render(<App content={sampleContent} />);
    const box = screen.getByRole('searchbox', { name: 'Filter skills' });

    await user.type(box, 'cobol');
    expect(screen.getByRole('status')).toHaveTextContent('No skills match.');

    await user.clear(box);
    expect(screen.getByRole('status')).toHaveTextContent('4 skills shown');
  });
});

describe('live data', () => {
  it('lights the module and job LEDs while the content comes from the API, and not otherwise', () => {
    const lit = (container: HTMLElement) => container.querySelectorAll('[class*="ledLive"]').length;
    const live = render(
      <App content={sampleContent} dataSource={{ kind: 'live', version: '1.0.0' }} />,
    );
    // two skill modules and two jobs
    expect(lit(live.container)).toBe(4);
    live.unmount();
    const offline = render(<App content={sampleContent} dataSource={{ kind: 'offline' }} />);
    expect(lit(offline.container)).toBe(0);
    offline.unmount();
    const none = render(<App content={sampleContent} />);
    expect(lit(none.container)).toBe(0);
  });

  it('lights the LED beside the dates of every job, like the other live-data LEDs', () => {
    const jobLeds = () =>
      screen.getByRole('region', { name: 'Experience' }).querySelectorAll('[class*="ledLive"]')
        .length;
    const live = render(
      <App content={sampleContent} dataSource={{ kind: 'live', version: '1.0.0' }} />,
    );
    expect(jobLeds()).toBe(2);
    live.unmount();
    render(<App content={sampleContent} dataSource={{ kind: 'offline' }} />);
    expect(jobLeds()).toBe(0);
  });
});
