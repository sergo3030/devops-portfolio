import type { Content } from './generated/content';

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

/**
 * A cheap structural check for data that did not come from this build, such as the API response.
 * The full contract is the generated JSON Schema, and a test checks that this guard accepts
 * the real snapshot that the schema accepts.
 */
export function isContent(value: unknown): value is Content {
  return (
    isRecord(value) &&
    value.version === 1 &&
    isRecord(value.profile) &&
    ['links', 'skills', 'experience', 'case_studies', 'languages'].every((key) =>
      Array.isArray(value[key]),
    )
  );
}
