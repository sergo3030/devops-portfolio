import type { Content } from './generated/content';

/** Small, made-up content for tests. The real content only ever comes from the approved snapshot. */
export const sampleContent: Content = {
  version: 1,
  profile: {
    name: 'Test Person',
    title: 'DevOps Engineer',
    summary: 'Builds platforms.',
    country: 'Nowhere',
  },
  links: [{ label: 'Code', url: 'https://example.com/code' }],
  skills: [
    { category: 'Containers', items: ['Kubernetes', 'Docker'] },
    { category: 'Observability', items: ['Prometheus', 'Grafana'] },
  ],
  experience: [
    { employer: 'Old Co', role: 'Engineer', start: '2018-12', end: '2022-01', bullets: ['Did A.'] },
    { employer: 'New Co', role: 'Lead', start: '2024-03', end: 'present', bullets: ['Did B.'] },
  ],
  case_studies: [],
  languages: ['English', 'Hebrew'],
};

export const emptyContent: Content = {
  version: 1,
  profile: {},
  links: [],
  skills: [],
  experience: [],
  case_studies: [],
  languages: [],
};

export const withCaseStudy: Content = {
  ...sampleContent,
  case_studies: [
    {
      id: 'upgrade',
      title: 'A cluster upgrade',
      summary: 'Moved four versions.',
      sections: [{ heading: 'Result', paragraphs: ['It worked.'] }],
    },
  ],
};
