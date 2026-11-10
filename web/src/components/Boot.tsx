import styles from './Boot.module.css';

/**
 * The boot screen: a bar of ticks that fills once while the page loads, then fades away. It is pure
 * decoration, drawn and removed by CSS alone (no script), carries no text, and is hidden from
 * assistive technology. It never blocks a click, and a visitor who prefers reduced motion never sees it.
 */
export function Boot() {
  return (
    <div className={styles.boot} aria-hidden="true">
      <span className={styles.logo} />
      <span className={styles.track}>
        <span className={styles.fill} />
      </span>
    </div>
  );
}
