/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Absolute origin of the API, set at build time once it exists (task 14). */
  readonly VITE_API_URL?: string;
}
