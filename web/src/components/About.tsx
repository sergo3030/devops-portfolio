import type { About as AboutContent } from '../generated/content';
import styles from './About.module.css';
import { ArchitectureDiagram } from './ArchitectureDiagram';
import { Section } from './Section';

export const ABOUT_TITLE = 'About this project';

type Props = { about: AboutContent | null | undefined };

/**
 * Renders nothing until at least one section is published (every line is owner-approved). The first
 * section is the summary box: its first paragraph is the summary and any others are small notes.
 * Every other section is a small card.
 */
export function About({ about }: Props) {
  if (!about || about.sections.length === 0) return null;
  const [summary, ...topics] = about.sections;
  const [lead, ...notes] = summary?.paragraphs ?? [];
  return (
    <Section heading={about.title ?? ABOUT_TITLE} id="about">
      <div className={styles.layout}>
        {summary ? (
          <div className={styles.summary}>
            <h3 className={styles.summaryHeading}>{summary.heading}</h3>
            {lead ? <p className={styles.lead}>{lead}</p> : null}
            {notes.map((note) => (
              <p key={note} className={styles.note}>
                {note}
              </p>
            ))}
          </div>
        ) : null}
        <div className={styles.band}>
          <ArchitectureDiagram />
        </div>
        {topics.length > 0 ? (
          <div className={styles.cards}>
            {topics.map((topic) => (
              <div key={topic.heading} className={styles.card}>
                <h3 className={styles.cardHeading}>{topic.heading}</h3>
                {topic.paragraphs.map((paragraph) => (
                  <p key={paragraph}>{paragraph}</p>
                ))}
              </div>
            ))}
          </div>
        ) : null}
      </div>
    </Section>
  );
}
