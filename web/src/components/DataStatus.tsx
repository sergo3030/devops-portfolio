import type { DataSource } from '../live';
import styles from './DataStatus.module.css';

type Props = { source: DataSource };

/** Says where the data on the page comes from. It sits at the bottom so a late answer never moves the content. */
export function DataStatus({ source }: Props) {
  if (source.kind === 'none') return null;
  return (
    <footer className={styles.footer}>
      <p role="status" className={source.kind === 'offline' ? styles.offline : styles.live}>
        {source.kind === 'live'
          ? `Live from API${source.version ? ` · version ${source.version}` : ''}`
          : 'API offline: showing the saved copy'}
      </p>
    </footer>
  );
}
