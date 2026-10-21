# Web

A static React site (Vite, React 19, TypeScript) that shows the published content. It is
built to GitHub Pages in task 13. It works with the API off: the content is embedded at build
time, and the page swaps in live data from the API when it answers (see "Live data").

## Live data (D32)

`Root` renders the saved copy at once, then `useLiveContent` fetches `/content` and `/health`
with a 5 s deadline. The line at the bottom of the page says what happened:

| State | When | Line |
|---|---|---|
| none | no API configured (production build without `VITE_API_URL`), or the request is still running | nothing |
| live | `/content` answered and passed the guard | "Live from API · version X" (no version if `/health` failed) |
| offline | network error, non-200, too slow, not JSON, or failed the guard | "API offline: showing the saved copy" |

In development the API address is `/api` (proxied to `just api-dev`). A production build uses
`VITE_API_URL`, which must be an absolute origin (see `web/.env.example`). The API needs CORS for
the site's origin before a deployed site can call it (task 16).

## Commands

| Command | What it does |
|---|---|
| `just web-content` | Builds the snapshot the site embeds (`web/src/generated/content.json`, approved lines only) |
| `just web-dev` | Starts the dev server. Run `just api-dev` too for live data. `/api` is proxied to the API, so no CORS is needed |
| `just web-check` | Everything CI runs: install from the lock file, ESLint, Prettier, TypeScript, tests, build, bundle budget |
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

`VITE_API_URL` is not set for this build, so the deployed site shows the saved copy and no status
line. Task 14 creates the API and task 16 adds CORS for the site origin; setting the variable then
turns the live data on.

## Dependencies

All versions are exact and `ignore-scripts` is on, so no package can run code when installed.
`npm audit --omit=dev` runs in CI (production dependencies only). ESLint 9 and TypeScript 6.0.3
are held back from the next major on purpose (D31).
