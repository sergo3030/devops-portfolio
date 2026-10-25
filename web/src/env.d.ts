/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Absolute origin of the API, set at build time (committed in `.env.production`). */
  readonly VITE_API_URL?: string;
}
