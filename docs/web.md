# Web

A static React site (Vite, React 19, TypeScript) that shows the published content. It is
built to GitHub Pages in task 13. It works with the API off: the content is embedded at build
time, and the page swaps in live data from the API when it answers (see "Live data").

## Live data (D32)

`Root` renders the saved copy at once, then `useLiveContent` fetches `/content`, then `/health`,
with one 8 s deadline (D44). The line at the bottom of the page says what happened:

| State | When | Line |
|---|---|---|
| none | no API configured (build without `VITE_API_URL`), or the request is still running | nothing |
| live | `/content` answered and passed the guard | "Live from API · version X" (no version if `/health` failed) |
| offline | network error, non-200, too slow, not JSON, or failed the guard | "API offline: showing the saved copy" |

In development the API address is `/api` (proxied to `just api-dev`). A production build reads
`VITE_API_URL` from the committed file `web/.env.production`: an absolute origin, no trailing slash.
The address is public by design (it is in the page's JavaScript and in its Content-Security-Policy),
and the API allows the site's origin through CORS (D43). The build writes the same origin into
`connect-src`, and `npm run check:page` fails if the bundle or the policy does not match the file.

The function URL changes whenever the function is destroyed and created again (a teardown and
recreate, `docs/runbook-prod.md`). Until `web/.env.production` is updated in a pull request the
site shows "API offline: showing the saved copy", which is the intended fallback and not an outage.

The two requests run one after the other, not together: the function allows two concurrent
executions, and on a cold start two requests at once would use both for one visitor.

## End-to-end test (task 17, D45)

`web/e2e/site.e2e.ts` drives the built site in a real Chrome (Playwright) against a running API.
It is the only test in which the Content-Security-Policy, CORS, the fetch options and the status
line all have to work together. It checks that:

- the page shows the content and the version that the API serves, with no console error (a CSP or
  CORS violation would be one);
- the page asks for `/content` first and `/health` after it, never together;
- with the API unreachable, answering 500, or answering something that is not the content, the
  page says "API offline: showing the saved copy" and is still the portfolio.

In CI the job `e2e (stack, site)` starts the container with `docker-compose.e2e.yml`, which only
adds `CORS_ALLOW_ORIGINS=http://127.0.0.1:4173` (the origin of `vite preview`; the image allows
the real site only). Playwright uses the Chrome that the runner image has, so no browser is
downloaded. The suite does not retry: a flaky end-to-end test hides what it exists to show.

Locally (needs Chrome): start the API with the override and run the test.

```bash
CORS_ALLOW_ORIGINS=http://127.0.0.1:4173 just api-dev   # in one terminal
just web-e2e                                            # in another
```

What it does not cover: the real function URL and the deployed site. A standing check of those
is task 17's second part (the `synthetic` workflow).

## Commands

| Command | What it does |
|---|---|
| `just web-content` | Builds the snapshot the site embeds (`web/src/generated/content.json`, approved lines only) |
| `just web-dev` | Starts the dev server. Run `just api-dev` too for live data. `/api` is proxied to the API, so no CORS is needed |
| `just web-check` | Everything CI runs: install from the lock file, ESLint, Prettier, TypeScript, tests, build, bundle budget, built-page wiring check |
| `just web-e2e` | The end-to-end test in Chrome against a running API (see above) |
| `just schema-export` | Regenerates `content/schema/published.schema.json` from the API models |

## The contract with the API

```
Pydantic models  ->  content/schema/published.schema.json  ->  web/src/generated/content.ts
(app/portfolio_api)      (committed, a test keeps it fresh)       (generated, not committed)
```

A change to the API models changes the schema file (the Python test fails until it is
committed), and the site regenerates its types from it before every type check, test and build.
The snapshot is also validated against the schema in a test, and a small guard checks data
that arrives at run time.

## Layout

```
web/
  index.html           %TITLE%, %DESCRIPTION% and %CSP% are filled at build time (vite.config.ts)
  scripts/             bundle size budget check
  src/
    styles/            tokens.css (the design tokens) and global.css
    App.tsx            a pure function of its props: { content }
    components/        Header, Experience (timeline, newest first), Skills (text filter),
                       CaseStudies (renders nothing until one is published), Languages, Section
    lib/               formatPeriod, newestFirst, filterSkills (plain functions, unit-tested)
    fixtures.ts        made-up content for tests
    content.ts         loads the embedded snapshot
    guard.ts           shape check for data fetched at run time
    generated/         content.json (snapshot) and content.ts (types), both git-ignored
```

## Rules that keep a redesign cheap (D30)

- Colours, spacing and type are CSS variables in `tokens.css`. Components use logical
  properties, so a right-to-left language or a new layout does not mean a rewrite.
- Components take data as props and never read `window` or `document` while rendering. A test
  renders the app on the server to keep it that way.
- Page title, description and the Content-Security-Policy come from the content snapshot and
  the API origin at build time, so no public text skips the approval gate.
- Bundle budget: 90 KB JavaScript and 15 KB CSS, gzipped. `npm run check:size` fails above it.

## Deploy (task 13, D33)

`.github/workflows/pages.yml` publishes the site to https://sergo3030.github.io/devops-portfolio/
after a merge to `main` that touches `web/`, `content/`, the verify script or the workflow itself,
and on demand from the Actions tab (from `main`: the `github-pages` environment refuses other
branches).

| Job | Does |
|---|---|
| `build (site)` | Builds the snapshot (approved lines only), `npm ci`, build, bundle budget, uploads `web/dist` and records the SHA-256 of `index.html` |
| `deploy (github-pages)` | Publishes the artifact, then `scripts/verify-site.sh` fetches the live page (retrying up to 90 s while the CDN catches up), requires it to be byte-identical to the built `index.html`, and loads every script and stylesheet it references |

The private content denylist cannot run in CI. Before a merge that changes `content/`, run
`just content-check` on the laptop: the merge publishes the result.

The build reads `VITE_API_URL` from `web/.env.production` (task 16b), so the deployed site shows
"Live from API" with the running version. `npm run check:page` runs after the build.

## Dependencies

All versions are exact and `ignore-scripts` is on, so no package can run code when installed.
`npm audit --omit=dev` runs in CI (production dependencies only). ESLint 9 and TypeScript 6.0.3
are held back from the next major on purpose (D31).
