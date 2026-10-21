// A size budget for the built site, so a redesign cannot quietly make it heavy.
import { readdirSync, readFileSync } from 'node:fs';
import { gzipSync } from 'node:zlib';

const BUDGET_KB = { '.js': 90, '.css': 15 };
const dir = new URL('../dist/assets/', import.meta.url);

const totals = { '.js': 0, '.css': 0 };
for (const name of readdirSync(dir)) {
  const extension = name.slice(name.lastIndexOf('.'));
  if (extension in totals) totals[extension] += gzipSync(readFileSync(new URL(name, dir))).length;
}

let failed = false;
for (const [extension, bytes] of Object.entries(totals)) {
  const kb = bytes / 1024;
  const budget = BUDGET_KB[extension];
  const over = kb > budget;
  failed ||= over;
  console.log(
    `${extension}: ${kb.toFixed(1)} KB gzip (budget ${budget} KB)${over ? '  OVER BUDGET' : ''}`,
  );
}
process.exit(failed ? 1 : 0);
