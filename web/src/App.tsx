import styles from './App.module.css';
import { CaseStudies } from './components/CaseStudies';
import { Experience } from './components/Experience';
import { Header } from './components/Header';
import { Languages } from './components/Languages';
import { Skills } from './components/Skills';
import type { Content } from './generated/content';

type Props = { content: Content };

/**
 * A pure component: everything it shows comes from the `content` prop, and it touches no browser
 * globals, so it can also be rendered on a server at build time.
 */
export function App({ content }: Props) {
  return (
    <main className={styles.page}>
      <Header profile={content.profile} links={content.links} />
      <Experience jobs={content.experience} />
      <Skills groups={content.skills} />
      <CaseStudies studies={content.case_studies} />
      <Languages languages={content.languages} />
    </main>
  );
}
