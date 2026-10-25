// Checks that the built site is wired to the API it is meant to call: the address in
// `.env.production` must be in the bundle, and the page's Content-Security-Policy must let the
// page connect to exactly that origin. Without the second part the browser would block every call
// and the site would quietly show the saved copy.
import { existsSync, readdirSync, readFileSync } from 'node:fs';

const root = new URL('../', import.meta.url);
const read = (path) => readFileSync(new URL(path, root), 'utf-8');

const fail = (message) => {
  console.error(`BUILT PAGE CHECK FAILED: ${message}`);
  process.exit(1);
};

const configured = existsSync(new URL('.env.production', root))
  ? /^VITE_API_URL=(\S+)$/m.exec(read('.env.production'))?.[1]
  : undefined;
const html = read('dist/index.html');
const policy = /http-equiv="Content-Security-Policy"\s+content="([^"]*)"/.exec(html)?.[1];
if (!policy) fail('dist/index.html has no Content-Security-Policy');
const connect = /(?:^|;\s*)connect-src ([^;]*)/.exec(policy)?.[1].split(' ');
if (!connect) fail('the Content-Security-Policy has no connect-src');

const assets = new URL('dist/assets/', root);
const bundle = readdirSync(assets)
  .filter((name) => name.endsWith('.js'))
  .map((name) => readFileSync(new URL(name, assets), 'utf-8'))
  .join('\n');

if (!configured) {
  if (connect.join(' ') !== "'self'") fail(`no API is configured but connect-src is ${connect}`);
  console.log('no API configured: the site calls only itself');
} else {
  const origin = new URL(configured).origin;
  if (!/^https:\/\/[a-z0-9.-]+\.on\.aws$/.test(origin))
    fail(`${origin} is not a Lambda function URL`);
  if (connect.join(' ') !== `'self' ${origin}`)
    fail(`connect-src is "${connect.join(' ')}", expected 'self' ${origin}`);
  if (!bundle.includes(origin)) fail(`the bundle does not contain ${origin}`);
  console.log(`ok: the site calls ${origin} and its Content-Security-Policy allows exactly that`);
}
