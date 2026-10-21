import { useId, type ReactNode } from 'react';
import styles from './Section.module.css';

type Props = { heading: string; children: ReactNode };

/** A page section with a visible heading that names the region for screen readers. */
export function Section({ heading, children }: Props) {
  const headingId = useId();
  return (
    <section aria-labelledby={headingId} className={styles.section}>
      <h2 id={headingId} className={styles.heading}>
        {heading}
      </h2>
      {children}
    </section>
  );
}
