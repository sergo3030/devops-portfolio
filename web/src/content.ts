import type { Content } from './generated/content';
import snapshot from './generated/content.json';
import { isContent } from './guard';

/** The saved copy of the approved content, built into the site. It always works offline. */
export function loadSnapshot(): Content {
  if (!isContent(snapshot)) {
    throw new Error('The built-in content snapshot does not match the content contract.');
  }
  return snapshot;
}
