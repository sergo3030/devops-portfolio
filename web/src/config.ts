/**
 * Where the API lives, or undefined when the site has no API to call. In development the
 * Vite proxy forwards `/api` to `just api-dev`. In a production build there is no API until
 * `VITE_API_URL` is set, and the site then shows the saved copy without claiming anything is down.
 */
export function apiBase(): string | undefined {
  const configured = import.meta.env.VITE_API_URL;
  if (configured) return configured.replace(/\/+$/, '');
  return import.meta.env.DEV ? '/api' : undefined;
}
