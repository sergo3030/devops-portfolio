import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { Ajv } from 'ajv';
import { loadSnapshot } from './content';
import snapshot from './generated/content.json';
import { isContent } from './guard';

const schema = JSON.parse(
  // A path, not a URL: in the jsdom environment `URL` is jsdom's class, which Node's fs rejects.
  readFileSync(resolve(import.meta.dirname, '../../content/schema/published.schema.json'), 'utf-8'),
) as object;
const validate = new Ajv({ strict: true }).compile(schema);

describe('the content contract', () => {
  it('accepts the built-in snapshot (JSON Schema generated from the API models)', () => {
    expect(validate(snapshot), JSON.stringify(validate.errors)).toBe(true);
    expect(isContent(snapshot)).toBe(true);
    expect(loadSnapshot().profile).toBeDefined();
  });

  it('rejects unknown fields, like the API models do', () => {
    expect(validate({ ...snapshot, approved: true })).toBe(false);
  });

  it('has a guard that rejects data of the wrong shape', () => {
    expect(isContent(null)).toBe(false);
    expect(isContent({ ...snapshot, version: 2 })).toBe(false);
    expect(isContent({ ...snapshot, skills: 'nope' })).toBe(false);
    expect(isContent({ ...snapshot, profile: null })).toBe(false);
  });
});
