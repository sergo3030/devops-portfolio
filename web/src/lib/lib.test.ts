import { formatPeriod, newestFirst } from './period';
import { countSkills, filterSkills } from './skills';

const groups = [
  { category: 'Containers', items: ['Kubernetes', 'Docker'] },
  { category: 'Observability', items: ['Prometheus', 'Grafana'] },
];

describe('formatPeriod', () => {
  it('writes year-months as month names with an en dash', () => {
    expect(formatPeriod('2024-03', 'present')).toBe('Mar 2024 – present');
    expect(formatPeriod('2018-12', '2022-01')).toBe('Dec 2018 – Jan 2022');
  });

  it('shows text that is not a year-month as it is', () => {
    expect(formatPeriod('2024-13', '2024')).toBe('2024-13 – 2024');
  });
});

describe('newestFirst', () => {
  it('sorts by start date, newest first, without changing the input', () => {
    const jobs = [{ start: '2018-12' }, { start: '2024-03' }, { start: '2020-06' }];
    expect(newestFirst(jobs).map((job) => job.start)).toEqual(['2024-03', '2020-06', '2018-12']);
    expect(jobs[0]?.start).toBe('2018-12');
  });
});

describe('filterSkills', () => {
  it('returns everything for an empty or blank query', () => {
    expect(filterSkills(groups, '')).toEqual(groups);
    expect(filterSkills(groups, '   ')).toEqual(groups);
  });

  it('matches items without regard to case and drops groups with no match', () => {
    expect(filterSkills(groups, 'KUBER')).toEqual([
      { category: 'Containers', items: ['Kubernetes'] },
    ]);
  });

  it('keeps a whole group when its name matches', () => {
    expect(filterSkills(groups, 'observ')).toEqual([groups[1]]);
  });

  it('returns nothing when nothing matches', () => {
    expect(filterSkills(groups, 'cobol')).toEqual([]);
  });

  it('counts the skills in a list of groups', () => {
    expect(countSkills(groups)).toBe(4);
    expect(countSkills([])).toBe(0);
  });
});
