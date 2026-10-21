import type { Experience as ExperienceItem } from '../generated/content';
import { formatPeriod, newestFirst } from '../lib/period';
import styles from './Experience.module.css';
import { Section } from './Section';

type Props = { jobs: ExperienceItem };

export function Experience({ jobs }: Props) {
  if (jobs.length === 0) return null;
  return (
    <Section heading="Experience">
      <ol className={styles.timeline}>
        {newestFirst(jobs).map((job) => (
          <li key={`${job.employer}-${job.start}`} className={styles.job}>
            <h3 className={styles.role}>
              {job.role}, {job.employer}
            </h3>
            <p className={styles.period}>{formatPeriod(job.start, job.end)}</p>
            <ul className={styles.bullets}>
              {job.bullets.map((bullet) => (
                <li key={bullet}>{bullet}</li>
              ))}
            </ul>
          </li>
        ))}
      </ol>
    </Section>
  );
}
