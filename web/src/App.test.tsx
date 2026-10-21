import { render, screen } from '@testing-library/react';
import { App } from './App';
import type { Content } from './generated/content';

const content: Content = {
  version: 1,
  profile: { name: 'Test Person', title: 'DevOps Engineer', summary: 'Builds platforms.' },
  links: [],
  skills: [],
  experience: [],
  case_studies: [],
  languages: [],
};

describe('App', () => {
  it('shows the name as the page heading, then the title and the summary', () => {
    render(<App content={content} />);
    expect(screen.getByRole('heading', { level: 1, name: 'Test Person' })).toBeInTheDocument();
    expect(screen.getByText('DevOps Engineer')).toBeInTheDocument();
    expect(screen.getByText('Builds platforms.')).toBeInTheDocument();
  });

  it('leaves out the summary when it is not published', () => {
    render(<App content={{ ...content, profile: { name: 'Test Person' } }} />);
    expect(screen.queryByText('Builds platforms.')).not.toBeInTheDocument();
  });
});
