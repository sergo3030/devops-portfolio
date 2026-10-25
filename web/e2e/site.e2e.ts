import { expect, test, type Page } from '@playwright/test';
import { API_URL } from '../playwright.config';

const SITE = '/devops-portfolio/';
const OFFLINE = 'API offline: showing the saved copy';

/** The status line at the bottom of the page (the page has another status for the skills filter). */
const dataStatus = (page: Page) => page.locator('footer [role="status"]');

/** Everything the browser reports as wrong: console errors (CSP and CORS violations land here). */
function watchProblems(page: Page): string[] {
  const problems: string[] = [];
  page.on('console', (message) => {
    if (message.type() === 'error') problems.push(message.text());
  });
  page.on('pageerror', (error) => problems.push(error.message));
  return problems;
}

test('shows the content and version the running API serves', async ({ page, request }) => {
  const problems = watchProblems(page);
  const content = (await (await request.get(`${API_URL}/content`)).json()) as {
    profile: { name: string };
  };
  const health = (await (await request.get(`${API_URL}/health`)).json()) as { version: string };

  await page.goto(SITE);

  await expect(dataStatus(page)).toHaveText(`Live from API · version ${health.version}`);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(content.profile.name);
  // Same-origin policy, CSP and CORS all had to agree for the answer to arrive without errors.
  expect(problems).toEqual([]);
});

test('asks for /content before /health, one at a time', async ({ page }) => {
  const paths: string[] = [];
  page.on('request', (request) => {
    if (request.url().startsWith(API_URL)) paths.push(new URL(request.url()).pathname);
  });
  await page.goto(SITE);
  await expect(dataStatus(page)).toContainText('Live from API');
  expect(paths).toEqual(['/content', '/health']);
});

for (const [name, fail] of [
  [
    'the API is unreachable',
    (route: import('@playwright/test').Route) => route.abort('connectionrefused'),
  ],
  [
    'the API answers with an error',
    (route: import('@playwright/test').Route) =>
      route.fulfill({
        status: 500,
        headers: { 'access-control-allow-origin': '*' },
        body: '{"detail":"boom"}',
      }),
  ],
  [
    'the API answers with something that is not the content',
    (route: import('@playwright/test').Route) =>
      route.fulfill({
        status: 200,
        headers: { 'access-control-allow-origin': '*', 'content-type': 'application/json' },
        body: '{"version":1,"profile":"nope"}',
      }),
  ],
] as const) {
  test(`falls back to the saved copy when ${name}`, async ({ page }) => {
    await page.route(`${API_URL}/**`, fail);
    await page.goto(SITE);

    await expect(dataStatus(page)).toHaveText(OFFLINE);
    // The page is still the portfolio, built from the content saved at build time.
    await expect(page.getByRole('heading', { level: 1 })).not.toBeEmpty();
    await expect(page.getByRole('heading', { level: 2 }).first()).toBeVisible();
  });
}
