import { defineConfig } from '@playwright/test';

/**
 * End-to-end test of the site against a running API (task 17). It drives a real Chrome (the one
 * installed on the machine, so nothing is downloaded) through the built site. The site is built
 * for the API at `API_URL` and served by `vite preview` on `SITE_PORT`; the API itself is started
 * by the caller (the CI job runs the container, `just web-e2e` documents the local way).
 */
export const API_URL = process.env.E2E_API_URL ?? 'http://127.0.0.1:8080';
const SITE_PORT = 4173;

export default defineConfig({
  testDir: 'e2e',
  testMatch: '*.e2e.ts',
  timeout: 30_000,
  retries: 0, // a flaky end-to-end test would hide the failures it exists to show
  reporter: [['list']],
  use: {
    baseURL: `http://127.0.0.1:${SITE_PORT}`,
    channel: 'chrome',
    trace: 'off',
  },
  webServer: {
    // A separate output directory, so the production `dist` is never overwritten.
    command: `npx vite build --outDir dist-e2e --emptyOutDir && npx vite preview --outDir dist-e2e --host 127.0.0.1 --port ${SITE_PORT} --strictPort`,
    url: `http://127.0.0.1:${SITE_PORT}/devops-portfolio/`,
    env: { VITE_API_URL: API_URL },
    reuseExistingServer: false,
    timeout: 120_000,
  },
});
