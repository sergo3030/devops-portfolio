import type { Content } from '../generated/content';
import styles from './Header.module.css';

type Props = Pick<Content, 'profile' | 'links'>;

export function Header({ profile, links }: Props) {
  const { name, title, country, summary } = profile;
  return (
    <header className={styles.header}>
      <h1 className={styles.name}>{name ?? 'Portfolio'}</h1>
      <p className={styles.meta}>
        {title ? <span>{title}</span> : null}
        {country ? <span>{country}</span> : null}
      </p>
      {summary ? <p className={styles.summary}>{summary}</p> : null}
      {links.length > 0 ? (
        <nav aria-label="Profiles">
          <ul className={styles.links}>
            {links.map((link) => (
              <li key={link.url}>
                <a href={link.url} target="_blank" rel="noopener noreferrer">
                  {link.label}
                </a>
              </li>
            ))}
          </ul>
        </nav>
      ) : null}
    </header>
  );
}
