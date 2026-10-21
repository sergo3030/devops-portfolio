import styles from './App.module.css';
import type { Content } from './generated/content';

type Props = { content: Content };

/**
 * A pure component: everything it shows comes from the `content` prop, and it touches no browser
 * globals, so it can also be rendered on a server at build time.
 */
export function App({ content }: Props) {
  const { name, title, summary } = content.profile;
  return (
    <main className={styles.page}>
      <header>
        <h1 className={styles.name}>{name}</h1>
        <p className={styles.title}>{title}</p>
      </header>
      {summary ? <p className={styles.summary}>{summary}</p> : null}
    </main>
  );
}
