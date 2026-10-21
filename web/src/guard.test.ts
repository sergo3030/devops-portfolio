import { emptyContent, sampleContent, withCaseStudy } from './fixtures';
import type { Content } from './generated/content';
import { isContent } from './guard';

const bad = (value: unknown) => value as never;

/** Each entry breaks one thing that a component reads. The guard must reject every one. */
const brokenWays: [string, (content: Content) => void][] = [
  ['an unknown version', (c) => void (c.version = bad(2))],
  ['a profile name that is not text', (c) => void (c.profile.name = bad(5))],
  ['a profile that is a list', (c) => void (c.profile = bad([]))],
  ['a link label that is not text', (c) => void (c.links[0]!.label = bad(1))],
  ['a javascript: link', (c) => void (c.links[0]!.url = 'javascript:alert(1)')],
  ['a link that is not a URL', (c) => void (c.links[0]!.url = 'not a url')],
  ['a list entry that is null', (c) => void (c.skills[0] = bad(null))],
  ['skill items that are not a list', (c) => void (c.skills[0]!.items = bad('Docker'))],
  ['a job whose bullets are numbers', (c) => void (c.experience[0]!.bullets = bad([1]))],
  ['a job without an end date', (c) => void Reflect.deleteProperty(c.experience[0]!, 'end')],
  [
    'case study paragraphs that are not a list',
    (c) => void (c.case_studies[0]!.sections[0]!.paragraphs = bad('x')),
  ],
  ['a case study without an id', (c) => void Reflect.deleteProperty(c.case_studies[0]!, 'id')],
  ['languages that are numbers', (c) => void (c.languages = bad([1]))],
  ['languages that are text', (c) => void (c.languages = bad('English'))],
];

describe('isContent', () => {
  it.each([
    ['empty content', emptyContent],
    ['sample content', sampleContent],
    ['content with a case study', withCaseStudy],
    ['null profile fields', { ...emptyContent, profile: { name: null, country: null } }],
  ])('accepts %s', (_label, value) => {
    expect(isContent(value)).toBe(true);
  });

  it.each(brokenWays)('rejects %s', (_label, breakIt) => {
    const copy = structuredClone(withCaseStudy);
    breakIt(copy);
    expect(isContent(copy)).toBe(false);
  });

  it.each([null, undefined, 'text', 5, [], {}])('rejects %j', (value) => {
    expect(isContent(value)).toBe(false);
  });
});
