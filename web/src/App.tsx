import { useEffect, useRef } from 'react';
import styles from './App.module.css';
import { About, ABOUT_TITLE } from './components/About';
import { Boot } from './components/Boot';
import { CaseStudies } from './components/CaseStudies';
import { DataStatus } from './components/DataStatus';
import { Experience } from './components/Experience';
import { Header } from './components/Header';
import { Languages } from './components/Languages';
import { Skills } from './components/Skills';
import type { Content } from './generated/content';
import type { DataSource } from './live';
import type { Page } from './page';

type Props = { content: Content; dataSource?: DataSource; page?: Page };

/**
 * A pure component: everything it shows comes from its props, and it touches no browser
 * globals while rendering, so it can also be rendered on a server at build time. Which view is
 * shown is a prop too: the portfolio, or the page about the project when that has been published.
 */
export function App({ content, dataSource = { kind: 'none' }, page = 'home' }: Props) {
  const hasAbout = Boolean(content.about && content.about.sections.length > 0);
  const aboutTitle = content.about?.title ?? ABOUT_TITLE;
  const view: Page = hasAbout ? page : 'home';

  // When the view changes: move focus to the content, bring it into view if the visitor was
  // scrolled past it, and name the tab after the view.
  const body = useRef<HTMLDivElement>(null);
  const shown = useRef<Page>(view);
  const baseTitle = useRef<string | null>(null);
  useEffect(() => {
    baseTitle.current ??= document.title;
    document.title = view === 'about' ? `${aboutTitle} | ${baseTitle.current}` : baseTitle.current;
    if (shown.current === view) return;
    shown.current = view;
    const element = body.current;
    if (!element) return;
    element.focus({ preventScroll: true });
    if (element.getBoundingClientRect().top < 0) element.scrollIntoView();
  }, [view, aboutTitle]);

  return (
    <main className={styles.page}>
      <Boot />
      <Header
        profile={content.profile}
        links={content.links}
        skills={content.skills}
        {...(hasAbout ? { aboutTitle, current: view } : {})}
      />
      <div className={styles.manifest} ref={body} tabIndex={-1}>
        <div className={styles.sheet}>
          {view === 'about' ? (
            <About about={content.about} />
          ) : (
            <>
              <div className={styles.columns}>
                <div>
                  <Experience jobs={content.experience} />
                </div>
                <div>
                  <Skills groups={content.skills} />
                  <Languages languages={content.languages} />
                </div>
              </div>
              <CaseStudies studies={content.case_studies} />
            </>
          )}
        </div>
      </div>
      <DataStatus source={dataSource} />
    </main>
  );
}
