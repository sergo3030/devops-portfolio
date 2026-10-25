import { useId, type ReactNode } from 'react';
import styles from './Section.module.css';

type Props = { heading: string; children: ReactNode; id?: string };

/** A page section with a visible heading that names the region for screen readers. */
export function Section({ heading, children, id }: Props) {
  const headingId = useId();
  return (
    <section id={id} aria-labelledby={headingId} className={styles.section}>
      <h2 id={headingId} className={styles.heading}>
        {heading}
      </h2>
      {children}
    </section>
  );
}
