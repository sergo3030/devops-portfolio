import type { Content, SkillGroup } from '../generated/content';
import type { Page } from '../page';
import styles from './Header.module.css';

type Props = Pick<Content, 'profile' | 'links'> & {
  /** The skill groups the side modules are made from. Left out, the board has no side modules. */
  skills?: SkillGroup[];
  aboutTitle?: string;
  current?: Page;
};

/** How many skills a side module shows, and how many modules the board has. */
const MODULE_ITEMS = 3;
const MODULE_COUNT = 6;

/** The first groups with more than one skill: a single skill makes a poor module. */
export function moduleGroups(groups: SkillGroup[]): SkillGroup[] {
  return groups.filter((group) => group.items.length > 1).slice(0, MODULE_COUNT);
}

/** The first word on one line and the rest on the next, so the name fills the device. The text stays one name. */
function NameLines({ name }: { name: string }) {
  const [first, ...rest] = name.split(' ');
  if (first === undefined || rest.length === 0) return <>{name}</>;
  return (
    <>
      <span className={styles.line}>{first}</span>{' '}
      <span className={styles.line}>{rest.join(' ')}</span>
    </>
  );
}

/**
 * A module on the side of the board. It is decoration that repeats the Skills section, so it is
 * hidden from assistive technology and its words are drawn by the stylesheet from data attributes:
 * they are not read twice, and a search for a skill finds it once.
 */
function Module({ group }: { group: SkillGroup }) {
  return (
    <div className={styles.chip}>
      <p className={styles.chipHead}>
        <i className={styles.led} />
        <span data-text={group.category} />
      </p>
      <p className={styles.chipItems}>
        {group.items.slice(0, MODULE_ITEMS).map((item) => (
          <span key={item} data-text={item} />
        ))}
      </p>
      <span className={styles.ticks} />
      <span className={styles.wire} />
    </div>
  );
}

export function Header({ profile, links, skills = [], aboutTitle, current = 'home' }: Props) {
  const { name, title, country, summary } = profile;
  const modules = moduleGroups(skills);
  const half = Math.ceil(modules.length / 2);
  return (
    <header className={styles.header}>
      <div className={styles.wall}>
        {aboutTitle ? (
          <div className={styles.top}>
            <nav className={styles.pages} aria-label="Pages">
              <ul>
                <li>
                  <a
                    className={styles.pageLink}
                    href="#top"
                    aria-current={current === 'home' ? 'page' : undefined}
                  >
                    Portfolio
                  </a>
                </li>
                <li>
                  <a
                    className={styles.pageLink}
                    href="#about"
                    aria-current={current === 'about' ? 'page' : undefined}
                  >
                    {aboutTitle}
                  </a>
                </li>
              </ul>
            </nav>
          </div>
        ) : null}
        <div
          className={modules.length > 0 ? `${styles.board} ${styles.withModules}` : styles.board}
        >
          {modules.length > 0 ? (
            <div className={`${styles.side} ${styles.left}`} aria-hidden="true">
              {modules.slice(0, half).map((group) => (
                <Module key={group.category} group={group} />
              ))}
            </div>
          ) : null}
          <div className={styles.device}>
            <h1 className={styles.name}>
              <NameLines name={name ?? 'Portfolio'} />
            </h1>
            <p className={styles.meta}>
              {title ? (
                <span className={styles.title}>
                  <i className={styles.ledOn} aria-hidden="true" />
                  {title}
                </span>
              ) : null}
              {country ? <span>{country}</span> : null}
            </p>
            {summary ? (
              <div className={styles.screen}>
                <p className={styles.summary}>{summary}</p>
              </div>
            ) : null}
            {links.length > 0 ? (
              <nav aria-label="Profiles">
                <ul className={styles.links}>
                  {links.map((link) => (
                    <li key={link.url}>
                      <a
                        className={styles.linkKey}
                        href={link.url}
                        target="_blank"
                        rel="noopener noreferrer"
                      >
                        {link.label}
                      </a>
                    </li>
                  ))}
                </ul>
              </nav>
            ) : null}
          </div>
          {modules.length > 0 ? (
            <div className={`${styles.side} ${styles.right}`} aria-hidden="true">
              {modules.slice(half).map((group) => (
                <Module key={group.category} group={group} />
              ))}
            </div>
          ) : null}
        </div>
      </div>
    </header>
  );
}
