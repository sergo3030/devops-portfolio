import type { About as AboutContent } from '../generated/content';
import styles from './About.module.css';
import { Section } from './Section';

export const ABOUT_TITLE = 'About this project';

type Props = { about: AboutContent | null | undefined };

/** Renders nothing until at least one section is published (every line is owner-approved). */
export function About({ about }: Props) {
  if (!about || about.sections.length === 0) return null;
  return (
    <Section heading={about.title ?? ABOUT_TITLE} id="about">
      {about.sections.map((section) => (
        <div key={section.heading}>
          <h3 className={styles.heading}>{section.heading}</h3>
          {section.paragraphs.map((paragraph) => (
            <p key={paragraph}>{paragraph}</p>
          ))}
        </div>
      ))}
    </Section>
  );
}
