import type { CaseStudies as CaseStudyList } from '../generated/content';
import styles from './CaseStudies.module.css';
import { Section } from './Section';

type Props = { studies: CaseStudyList };

/** Renders nothing until a case study is published (employer approval is a content-gate rule). */
export function CaseStudies({ studies }: Props) {
  if (studies.length === 0) return null;
  return (
    <Section heading="Case studies">
      {studies.map((study) => (
        <article key={study.id} className={styles.study}>
          <h3 className={styles.title}>{study.title}</h3>
          <p>{study.summary}</p>
          {study.sections.map((section) => (
            <div key={section.heading}>
              <h4 className={styles.heading}>{section.heading}</h4>
              {section.paragraphs.map((paragraph) => (
                <p key={paragraph}>{paragraph}</p>
              ))}
            </div>
          ))}
        </article>
      ))}
    </Section>
  );
}
