import styles from './Languages.module.css';
import { Section } from './Section';

type Props = { languages: string[] };

export function Languages({ languages }: Props) {
  if (languages.length === 0) return null;
  return (
    <Section heading="Languages">
      <ul className={styles.list}>
        {languages.map((language) => (
          <li key={language}>{language}</li>
        ))}
      </ul>
    </Section>
  );
}
