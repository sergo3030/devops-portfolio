import { useSyncExternalStore } from 'react';

/** The site has two views: the portfolio itself, and the page about how the project is built. */
export type Page = 'home' | 'about';

/** The address `#about` opens the project page. Any other address, such as `#top`, opens the portfolio. */
export function pageFromHash(hash: string): Page {
  return hash === '#about' ? 'about' : 'home';
}

function subscribe(onChange: () => void): () => void {
  window.addEventListener('hashchange', onChange);
  return () => {
    window.removeEventListener('hashchange', onChange);
  };
}

/** The view the address bar asks for. It follows the back and forward buttons and link clicks. */
export function usePage(): Page {
  return useSyncExternalStore(
    subscribe,
    () => pageFromHash(window.location.hash),
    () => 'home',
  );
}
