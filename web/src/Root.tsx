import { App } from './App';
import { ErrorBoundary } from './components/ErrorBoundary';
import type { Content } from './generated/content';
import { useLiveContent } from './live';

type Props = { snapshot: Content; apiBase: string | undefined };

/**
 * The only part that talks to the network. The page starts from the saved copy and shows the
 * API's content once it has answered. If rendering the API's content ever fails, the saved
 * copy is shown instead of a blank page.
 */
export function Root({ snapshot, apiBase }: Props) {
  const { content, source } = useLiveContent(snapshot, apiBase);
  return (
    <ErrorBoundary fallback={<App content={snapshot} dataSource={{ kind: 'offline' }} />}>
      <App content={content} dataSource={source} />
    </ErrorBoundary>
  );
}
