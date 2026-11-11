# Web

A static React site (Vite, React 19, TypeScript) that shows the published content. It is
built to GitHub Pages in task 13. It works with the API off: the content is embedded at build
time, and the page swaps in live data from the API when it answers (see "Live data").

## Live data (D32)

`Root` renders the saved copy at once, then `useLiveContent` fetches `/content`, then `/health`,
with one 8 s deadline (D44). A bar that stays at the foot of the screen (it never moves the content) says what happened:

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

## The About section (task 19b, D50)

`About` renders `content.about` as **its own page**, not as a section of the portfolio. The address
`#about` opens it (`page.ts`, read with `useSyncExternalStore`), and any other address opens the
portfolio. The header has two links, Portfolio and About this project, with the current one marked
`aria-current="page"`. When the view changes the content takes focus, the tab title names the page,
and the window scrolls to the content if the visitor was below it. `App` stays pure: the view is a
`page` prop, and `Root` reads the address. `About` renders nothing, and the header shows no links,
until at least one section is published. The field is optional
everywhere on purpose: the site and the API deploy independently, so an API that is one version
behind serves content without `about`. When live content has none, `keepAbout` keeps the saved
copy's section, so the page does not lose it and does not call a harmless difference an outage. The
end-to-end test covers this with an API that answers without `about`.

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
  public/              the tab icon: favicon.svg, favicon-32.png and apple-touch-icon.png
  scripts/             bundle size budget check
  src/
    styles/            tokens.css (the design tokens) and global.css
    App.tsx            a pure function of its props: { content }
    assets/            the three fonts, self-hosted (see "Design"); steel-corrugated.png and the
                       Big Shoulders font are left from an earlier design and are no longer used
    components/        Header (the device and the side modules), Boot (the start-up screen),
                       Experience (timeline, newest first), Skills (text filter), CaseStudies
                       (renders nothing until one is published), Languages, Section
    styles/parts.module.css   the parts the board is made of (module, label, LED, key, well,
                       screen); components take them with `composes`
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

## Design: Warm circuit board

A greige board with a faint dot grid. Everything on it is a raised module lit from the top left, a
dark screen, a keycap, an LED, or a printed trace, and there is one accent, a burnt orange. It follows
a retro-computing landing page the owner chose (the Zajno "vector computer" shot), in warm instead of
cool greys. The published text is unchanged: the design adds no copy (the start-up screen has no
words). The colours, shadows and sizes are in `tokens.css`; the dark scheme turns the board into warm
charcoal and lightens the orange.

- **Fonts (self-hosted, SIL Open Font License 1.1, licences beside them in `src/assets/fonts/`):**
  Saira Semi Condensed, weight 700 only (the name, headings, job titles and the diagram's station
  names; its squared curves echo the rounded-square modules and keys), Figtree (body) and JetBrains
  Mono (labels, dates, the skill keys, the screen and the state labels). Latin subsets, 18 KB, 20 KB
  and 40 KB. The page's policy allows fonts only from its own server, which is why the files are in
  the repository. Bricolage Grotesque, the display font of the two earlier designs, was replaced on
  2026-11-10: its editorial shapes did not fit hardware panels (the owner's call).
- **Parts (`styles/parts.module.css`):** a *module* is a raised plate (18 px corners), a *label* is a
  small mono line in the case the text is written in, an *LED* is off or orange (no glow; steady, except the live-data
  LEDs, which pulse softly while the content comes from the API: the status bar's, the six skill
  modules' and the job modules'; lit only where something is live, current or working), a *key* moves down when pressed (36 px tall, a
  hero key 44), a *well* is sunk into the board, and a *screen* is dark glass with light mono text. A
  component that needs a part to differ sets the part's custom property (`--key-padding`,
  `--module-radius` and the others listed at the top of `parts.module.css`). It must not override the
  part's own properties: the part's stylesheet can load later, and the override is lost without a
  warning (this happened once and was fixed on 2026-11-10).
- **Orange and text:** orange is a signal colour (LEDs, traces, the request). As a fill it is only
  2.5:1 on the board, so text on an orange key uses the deeper orange `#b4501a` with light ink
  (4.8:1). Muted text is `#57524a`, 4.5:1 or more on every surface. A real-browser axe run (contrast
  included) found nothing on the home page and the About page in light, dark and at 390 px.
- **Layout:** the header, the body and the status bar share one width (80rem). The header is the page
  keys, then the board: one big module, the *device* (role and country, the name on
  two lines, a screen with the summary, and the two profile keys), with up to six skill modules beside
  it from 62rem, wired to it by printed traces. The modules are made from the first six skill groups
  that have more than one skill. From 62rem the experience sits beside the skills and languages.
  The About page is a summary module, the diagram on a full-width darker band, and small modules.
- **The side modules:** decoration that repeats the Skills section. They are hidden from assistive
  technology, and their words are drawn from data attributes by the stylesheet, so a screen reader
  does not read them twice and a search for a skill finds it once.
- **Skills filter:** a hidden skill leaves an empty dashed slot behind, so the shape of the whole
  list stays visible. The slots are decorative and hidden from screen readers.
- **Profile keys:** both are orange (the owner asked earlier for the two to match).
- **Motion:** one start-up. A boot screen (a logo and a bar of ticks) covers the page for 1.5 s and
  fades; then the modules rise in one by one, the traces draw themselves, the summary is revealed on
  the screen from top to bottom, a short orange signal runs along each trace twice, and the cursor
  starts to blink and keeps blinking for as long as the page is open. Apart from the cursor and the
  live-data LEDs the page is then still.
  The boot screen and every entrance are CSS only (no script), so the page is complete without them;
  the boot screen never blocks a click, and its length is `--boot` in `tokens.css`. Reduced motion
  removes the boot screen and every animation, pseudo-elements included. No inline styles (the policy
  forbids them): the order of the modules is set with `:nth-child` rules. Timing and easing are tokens:
  one curve, 150 ms press, 500 ms entrance, 60 ms step.
- **Polish pass (2026-11-10, with the `unslop` skill):** spacing moved onto the 4 px grid, shadows
  made neutral (no glow, no coloured shadow), labels set in sentence case with 0.02em tracking (the
  keys now read LinkedIn and GitHub), weights capped (display 700, everything else 400 to 600), radii
  set by the nested-radius rule, loops removed. Left as the owner's choices: the two equal orange
  profile keys, the side modules and traces, and the Saira Semi Condensed 700 display weight.
- **Tab icon:** a keycap with a squared S and one orange LED, drawn as `public/favicon.svg` (16 to
  128 px tested). The SVG carries a dark-theme rule, so on a dark browser it becomes a light keycap
  with a dark S. `favicon-32.png` and `apple-touch-icon.png` (180 px, no rounded corners, light
  variant) are fallbacks for browsers without SVG icons. All three are same-origin, so the page's
  `img-src 'self'` allows them, and declaring them stops the browser asking for `/favicon.ico`.
- **Known limit:** resizing the window across 62rem shows and hides the side modules, and they power
  on again when they return.

## The About layout and the architecture diagram

`About` shows the **first** section of `about` as the summary box: its first paragraph is the
summary, and any further paragraphs of that section are small notes under it. Every other section is
a small card, so keep them to a sentence or two. There is no schema field for this: it is a
convention, so the order in `content.yaml` matters.

`ArchitectureDiagram` (between the summary box and the cards, inside `About`, so it disappears with
it) is a station map of how a request travels, one step at a time. The request line runs from the
client through GitHub Pages and a content fork to the Function URL and the Lambda service, then into
one box, the Lambda container, which holds six numbered steps: the Web Adapter and the FastAPI
layers (security headers, the read-only check, CORS, the router, and the content in memory). It has
four stories (cold start and request, warm request, POST refused, start-up failure), a Lambda phase
indicator (Init, Invoke, Idle, Shutdown), Restart, Back, Replay (the current step) and Next buttons, a
step slider, a legend of the states, and a table with the state of each component. The map is drawn as SVG in the site's own style.

- **Data:** `components/architecture.ts` holds the stories. A step moves a dot along a path, says what
  happened, and lists only the states that changed, so adding a story means adding steps there.
  `components/metro.ts` holds the map's geometry; the dot also passes GitHub Pages and the fork on
  the way from the client to the Function URL, and the container's front door on the way in.
- **Look:** the card is a module. The stories are keys (the chosen one stays pressed in, with a lit
  LED), the phases are small mono chips (the active one is a dark screen chip), and the buttons sit
  on a dark screen with the slider's groove beneath. Back, Restart and the rest keep their names.
- **Layout:** from 62rem the map is one wide picture: the line along the top, the container box on
  the right, and the grey lines around the request path (the site's Pages workflow, the deploy line
  that splits to both the Function URL and the Lambda, CloudWatch Logs, and a cost guard note). From
  75rem the controls and the words about the step sit in a column beside the picture, so the whole
  card (stories, phases, map and controls) fits one screen and the words can be read while the dot
  moves; a short screen shrinks the map further. From 62rem to 75rem the controls sit above it.
  Below 62rem a second, tall picture is used (one column, without the grey lines, which become a
  short list under it). Both pictures are drawn from the same data, so the dot moves in both.
  The tall picture is taller than a phone screen, so there the buttons, the slider and the words
  about the step are pinned at the top of the screen (the `dock`, `position: sticky`) while the map
  scrolls under it. Each step then scrolls the page until the part that lights up is in view under
  the dock and above the status bar (`components/follow.ts` holds the arithmetic; the scroll is
  smooth, instant under reduced motion, and skipped from 62rem up, where nothing is pinned). The
  words have a fixed height per width band, measured from the longest of the four stories, so the
  dock never changes height and the map never moves under it.
- **States:** each stop shows its state label in a pill. A stop that is not running has a dashed
  outline, a ready one is filled grey, a working one is filled orange (and flickers like an LED),
  and an error is filled dark with a cross. The words, the legend and the table say the same, so
  colour is never the only signal.
- **The request:** a small envelope in a round orange badge that tilts and sends out a ring while it
  travels. The request line is a light trace in a groove, and a short orange signal runs along it all
  the time; reduced motion hides it.
- **Motion:** nothing moves by itself, and there is no auto-play. The visitor steps with Next and
  Back or the slider. Next and Replay send the request dot along the path of the step (the dot also
  passes GitHub Pages, the fork and the container's front door); Back, Restart and the slider only show the
  step. Next is the orange main button. The dot is skipped for a visitor who prefers reduced motion. It
  is moved through the element's style object, not a style attribute in the markup, because the
  page's policy forbids inline styles.
- **No jumping:** the caption, the pills and the table rows have fixed minimum sizes. The layout was
  measured across every step of every story at 768, 1024, 1280 and 1440 px (no change) and at
  390 px (about 10 px of change in the state table).
- **Facts:** the layer order, the refusal codes, the adapter settings and the 8 s limit were checked
  against the repository and the Lambda Web Adapter documentation. The deploy
  line follows the real workflows (release tag, image build, ECR, OIDC role, tofu apply) and the
  Function URL is created by `infra/prod/lambda.tf`. Estimates that were not checked are left out of
  the public text. The cold start of about 4 s was measured on this project
  (`docs/runbook-prod.md`, "Cold start").
- **Wording:** it is public text that is not in `content.yaml`, so change it only with the owner's
  approval. The words on the map (stop names, the fork note, "Cost guard", "Saved copy, if the API
  is offline") are new and not yet approved.

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

**One override.** `package.json` forces `minimatch ^11.0.1` for `@typescript-eslint/typescript-estree`
(GHSA-g3hv-75wg-m249, a denial of service through a crafted glob, fixed in 11.0.1). The package asks
for `^10.2.2`, so a normal update cannot reach the fix, and its latest release (8.72.2) still asks for
it. The package is a dev dependency used only by the linter and never reaches the built site. The
override was checked with the linter, the tests and the build. **Revisit** when typescript-eslint
accepts minimatch 11: remove the `overrides` block, run `npm install --package-lock-only`, and run
`just web-check`.
