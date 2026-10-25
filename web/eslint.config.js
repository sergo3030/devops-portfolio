import js from '@eslint/js';
import jsxA11y from 'eslint-plugin-jsx-a11y';
import reactHooks from 'eslint-plugin-react-hooks';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['dist', 'dist-e2e', 'test-results', 'node_modules', 'src/generated'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  reactHooks.configs.flat.recommended,
  jsxA11y.flatConfigs.recommended,
  { files: ['**/*.{ts,tsx}'], languageOptions: { globals: globals.browser } },
  {
    files: [
      'scripts/**/*.mjs',
      'vite.config.ts',
      'eslint.config.js',
      'playwright.config.ts',
      'e2e/**/*.ts',
    ],
    languageOptions: { globals: globals.node },
  },
);
