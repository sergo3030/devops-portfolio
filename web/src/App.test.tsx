import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { App } from './App';
import { emptyContent, sampleContent, withCaseStudy } from './fixtures';

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
