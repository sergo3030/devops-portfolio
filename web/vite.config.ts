import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import react from '@vitejs/plugin-react';
import { loadEnv, type Plugin } from 'vite';
import { defineConfig } from 'vitest/config';

const SNAPSHOT = fileURLToPath(new URL('./src/generated/content.json', import.meta.url));

const escapeAttribute = (text: string): string =>
  text.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');

/**
 * All public text in index.html flows from the approved content snapshot, so the page title,
 * the description and the link preview can never carry words that skipped the approval gate.
 * It also writes the Content-Security-Policy: scripts, styles, fonts and images come from the
 * site itself, and the only outside host the page may call is the API origin (if configured).
 */
function pageMetadata(apiUrl: string | undefined, isBuild: boolean): Plugin {
  return {
    name: 'page-metadata',
    transformIndexHtml(html) {
      if (!existsSync(SNAPSHOT)) {
        throw new Error('src/generated/content.json is missing. Run `just web-content` first.');
      }
      const content = JSON.parse(readFileSync(SNAPSHOT, 'utf-8')) as {
        profile: { name?: string; title?: string; summary?: string };
      };
      const title = [content.profile.name, content.profile.title].filter(Boolean).join(' · ');
      const apiOrigin = apiUrl ? new URL(apiUrl).origin : '';
      const policy = isBuild
        ? [
            "default-src 'self'",
            "script-src 'self'",
            "style-src 'self'",
            "img-src 'self' data:",
            "font-src 'self'",
            `connect-src 'self' ${apiOrigin}`.trim(),
            "base-uri 'none'",
            "form-action 'none'",
            "object-src 'none'",
          ].join('; ')
        : // The dev server injects inline scripts for hot reload, so the policy is relaxed there.
          "default-src * 'unsafe-inline' 'unsafe-eval' data: blob:";
      return html
        .replaceAll('%TITLE%', escapeAttribute(title || 'Portfolio'))
        .replaceAll('%DESCRIPTION%', escapeAttribute(content.profile.summary ?? ''))
        .replaceAll('%CSP%', escapeAttribute(policy));
    },
  };
}

export default defineConfig(({ command, mode }) => {
  const env = loadEnv(mode, process.cwd(), 'VITE_');
  return {
    // The site lives at https://<user>.github.io/devops-portfolio/ on GitHub Pages.
    base: env.VITE_BASE ?? '/devops-portfolio/',
    plugins: [react(), pageMetadata(env.VITE_API_URL, command === 'build')],
    server: {
      // Local development talks to `just api-dev` through this proxy, so no CORS is needed.
      proxy: { '/api': { target: 'http://127.0.0.1:8080', rewrite: (path) => path.slice(4) } },
    },
    test: {
      environment: 'jsdom',
      globals: true,
      setupFiles: ['./src/test-setup.ts'],
    },
  };
});
