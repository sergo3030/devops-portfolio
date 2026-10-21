import styles from './App.module.css';
import { CaseStudies } from './components/CaseStudies';
import { DataStatus } from './components/DataStatus';
import { Experience } from './components/Experience';
import { Header } from './components/Header';
import { Languages } from './components/Languages';
import { Skills } from './components/Skills';
import type { Content } from './generated/content';
import type { DataSource } from './live';

type Props = { content: Content; dataSource?: DataSource };

/**
 * A pure component: everything it shows comes from its props, and it touches no browser
 * globals, so it can also be rendered on a server at build time.
 */
export function App({ content, dataSource = { kind: 'none' } }: Props) {
  return (
    <main className={styles.page}>
      <Header profile={content.profile} links={content.links} />
      <Experience jobs={content.experience} />
      <Skills groups={content.skills} />
      <CaseStudies studies={content.case_studies} />
      <Languages languages={content.languages} />
      <DataStatus source={dataSource} />
    </main>
  );
}
