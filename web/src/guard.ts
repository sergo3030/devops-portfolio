import type { Content } from './generated/content';

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const isString = (value: unknown): value is string => typeof value === 'string';

const isOptionalString = (value: unknown): boolean =>
  value === undefined || value === null || isString(value);

const isStrings = (value: unknown): value is string[] =>
  Array.isArray(value) && value.every(isString);

function isListOf(value: unknown, check: (item: Record<string, unknown>) => boolean): boolean {
  return Array.isArray(value) && value.every((item) => isRecord(item) && check(item));
}

/** Only web links. A `javascript:` URL in a link would run code when it is clicked. */
function isWebUrl(value: unknown): boolean {
  if (!isString(value)) return false;
  try {
    const { protocol } = new URL(value);
    return protocol === 'https:' || protocol === 'http:';
  } catch {
    return false;
  }
}

/**
 * A structural check of data that did not come from this build, such as the API response. It
 * checks every field the components read, so a bad response is rejected before it can break the
 * page, and it only lets web links through. The full contract is the generated JSON Schema: a
 * test checks that this guard accepts what the schema accepts and rejects what it rejects.
 */
export function isContent(value: unknown): value is Content {
  return (
    isRecord(value) &&
    value.version === 1 &&
    isRecord(value.profile) &&
    ['name', 'title', 'summary', 'country'].every((key) =>
      isOptionalString((value.profile as Record<string, unknown>)[key]),
    ) &&
    isListOf(value.links, (link) => isString(link.label) && isWebUrl(link.url)) &&
    isListOf(value.skills, (group) => isString(group.category) && isStrings(group.items)) &&
    isListOf(
      value.experience,
      (job) =>
        isString(job.employer) &&
        isString(job.role) &&
        isString(job.start) &&
        isString(job.end) &&
        isStrings(job.bullets),
    ) &&
    isListOf(
      value.case_studies,
      (study) =>
        isString(study.id) &&
        isString(study.title) &&
        isString(study.summary) &&
        isListOf(
          study.sections,
          (section) => isString(section.heading) && isStrings(section.paragraphs),
        ),
    ) &&
    isStrings(value.languages)
  );
}
