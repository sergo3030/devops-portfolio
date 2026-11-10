/**
 * The data behind the architecture diagram: how a request travels from a client to the code inside
 * the Lambda container, and four short stories about it. Each step moves the request along a path,
 * says what happened, and lists only the states that changed: a component keeps its state until a
 * later step changes it.
 *
 * Facts that were checked against the repository or the Lambda Web Adapter documentation are
 * stated. Anything that is only a reading of how Lambda behaves is worded without numbers.
 */
export type NodeId = 'c' | 'u' | 'l' | 'a' | 's1' | 's2' | 's3' | 's4' | 's5';
export type Family = 'client' | 'url' | 'lambda' | 'adapter' | 'layers';
export type Tone = 'idle' | 'ready' | 'working' | 'error';
export type Phase = 'Init' | 'Invoke' | 'Idle' | 'Shutdown';
export type NodeState = { label: string; tone: Tone; detail: string };
export type States = Record<NodeId, NodeState>;
export type Step = {
  phase?: Phase;
  time: string;
  heading: string;
  text: string;
  path?: NodeId[];
  hi: NodeId[];
  set: Partial<States>;
};
export type ScenarioKey = 'cold' | 'warm' | 'post' | 'fail';

export const NODE_IDS: readonly NodeId[] = ['c', 'u', 'l', 'a', 's1', 's2', 's3', 's4', 's5'];
export const PHASES: readonly Phase[] = ['Init', 'Invoke', 'Idle', 'Shutdown'];

export const NODE_NAMES: Record<NodeId, string> = {
  c: 'Client',
  u: 'Function URL',
  l: 'Lambda service',
  a: 'Web Adapter',
  s1: 'Security headers',
  s2: 'Read-only check',
  s3: 'CORS',
  s4: 'Router',
  s5: 'Content in memory',
};

/** Each kind of component has its own colour on the diagram card. */
export const NODE_FAMILY: Record<NodeId, Family> = {
  c: 'client',
  u: 'url',
  l: 'lambda',
  a: 'adapter',
  s1: 'layers',
  s2: 'layers',
  s3: 'layers',
  s4: 'layers',
  s5: 'layers',
};

const state = (label: string, tone: Tone, detail: string): NodeState => ({ label, tone, detail });
const notStarted = (): NodeState => state('None', 'idle', 'Not started');

const clientIdle = state('Idle', 'idle', "The visitor's browser");
const urlWaiting = state('Waiting', 'ready', 'Public address of the function');

const none: States = {
  c: clientIdle,
  u: urlWaiting,
  l: state('Idle', 'idle', 'No container exists'),
  a: notStarted(),
  s1: notStarted(),
  s2: notStarted(),
  s3: notStarted(),
  s4: notStarted(),
  s5: notStarted(),
};

const ready: Partial<States> = {
  s1: state('Ready', 'ready', 'Adds security headers to answers'),
  s2: state('Ready', 'ready', 'Allows GET and OPTIONS only'),
  s3: state('Ready', 'ready', 'Allows the site origin only'),
  s4: state('Ready', 'ready', 'Serves /health and /content'),
  s5: state('Ready', 'ready', 'Loaded and validated at start'),
};

const warm: States = {
  ...none,
  ...ready,
  l: state('Idle', 'idle', 'Container exists, kept for a while'),
  a: state('Waiting', 'ready', 'Idle between requests'),
};

const sent = (method: string, path: string): Partial<States> => ({
  c: state('Waiting for the answer', 'working', `Sent ${method} ${path}`),
  u: state('Received', 'working', 'Passes the request to Lambda'),
});

/** A request reaches a Lambda that has no container to run it. */
const requestArrivesCold = (method: string, path: string): Step => ({
  phase: 'Init',
  time: 'request',
  heading: 'A request arrives',
  text: "A visitor's browser calls the Function URL. Lambda finds no free container, so it starts one from the image.",
  path: ['c', 'u', 'l'],
  hi: ['c', 'u', 'l'],
  set: {
    ...sent(method, path),
    l: state('Starting', 'working', 'No free container, creating one'),
  },
});

/** A request reaches a Lambda that already has a container waiting. */
const requestArrivesWarm = (method: string, path: string): Step => ({
  phase: 'Invoke',
  time: 'request',
  heading: 'A request arrives',
  text: "A visitor's browser calls the Function URL, which hands the request to the Lambda service. A container is waiting, so the event goes to the adapter.",
  path: ['c', 'u', 'l', 'a'],
  hi: ['c', 'u', 'l', 'a'],
  set: {
    ...sent(method, path),
    l: state('Invoke', 'working', 'Passing the event on'),
    a: state('Converting', 'working', `Turns the event into HTTP ${method} ${path}`),
  },
});

const containerCreated: Step = {
  phase: 'Init',
  time: 'start',
  heading: 'Lambda creates the container',
  text: 'This is the Init phase: Lambda starts the container from the image, then the adapter extension, then the web app.',
  hi: ['l', 'a'],
  set: {
    l: state('Init', 'working', 'Starting the environment'),
    a: state('Starting', 'working', 'Started by Lambda as an extension'),
  },
};

const adapterReceives = (method: string, path: string): Step => ({
  phase: 'Invoke',
  time: 'request',
  heading: 'The adapter receives the event',
  text: 'The container is ready, so Lambda hands the waiting request to the adapter as an event.',
  path: ['l', 'a'],
  hi: ['l', 'a'],
  set: {
    l: state('Invoke', 'working', 'Passing the event on'),
    a: state('Converting', 'working', `Turns the event into HTTP ${method} ${path}`),
  },
});

const adapterCalls: Step = {
  time: 'request',
  heading: 'The adapter calls localhost:8080',
  text: 'It sends a normal HTTP request to the app. The first stop is the security-headers layer, which wraps everything.',
  path: ['a', 's1'],
  hi: ['a', 's1'],
  set: {
    a: state('Waiting', 'working', 'Waiting for the HTTP answer'),
    s1: state('Passing', 'working', 'Will add headers on the way back'),
  },
};

const readOnlyAllows: Step = {
  time: 'request',
  heading: 'The read-only check',
  text: 'GET is allowed. Any method other than GET or OPTIONS stops here with 405 (a body gives 413, very large headers 431, a long URL 414).',
  path: ['s1', 's2'],
  hi: ['s2'],
  set: { s2: state('Allowed', 'ready', 'GET is fine') },
};

const corsAllows: Step = {
  time: 'request',
  heading: 'CORS',
  text: 'The request carries the site origin, the one allowed origin, so the answer will carry the CORS headers.',
  path: ['s2', 's3'],
  hi: ['s3'],
  set: { s3: state('Origin allowed', 'ready', 'Site origin matches') },
};

const routerAnswers: Step = {
  time: 'request',
  heading: 'Router and content',
  text: 'The router matches GET /content and reads the validated content from memory. There is no database and no network call.',
  path: ['s3', 's4', 's5'],
  hi: ['s4', 's5'],
  set: {
    s4: state('Matched', 'ready', 'GET /content'),
    s5: state('Reading', 'working', 'Served from memory'),
  },
};

const answerGoesUp: Step = {
  time: 'request',
  heading: 'The answer goes back up',
  text: 'The JSON passes back up through the layers, and the security layer adds its headers last.',
  path: ['s5', 's4', 's3', 's2', 's1', 'a'],
  hi: ['s1', 'a'],
  set: {
    s1: state('Headers added', 'ready', 'Security headers on the answer'),
    a: state('Converting', 'working', 'Turns the HTTP answer into a response event'),
  },
};

const responseReturns = (outcome: NodeState, lambdaDetail: string, text: string): Step => ({
  time: 'request',
  heading: 'The response returns to the client',
  text,
  path: ['a', 'l', 'u', 'c'],
  hi: ['a', 'l', 'u', 'c'],
  set: {
    ...ready,
    c: outcome,
    u: urlWaiting,
    l: state('Invoke done', 'ready', lambdaDetail),
    a: state('Waiting', 'ready', 'Idle between requests'),
  },
});

const idleBetween: Step = {
  phase: 'Idle',
  time: 'later',
  heading: 'Idle between requests',
  text: 'Lambda keeps the container for a while and the app does no work until the next request. A new request reuses it with no start-up.',
  hi: ['l'],
  set: { l: state('Idle', 'idle', 'Container kept for a while') },
};

const shutdown: Step = {
  phase: 'Shutdown',
  time: 'after a long idle',
  heading: 'Shutdown',
  text: 'Lambda removes the container eventually. The adapter docs say it sends SIGTERM first so the app can stop cleanly. The next request is a cold start.',
  hi: ['l', 'a', 's1', 's2', 's3', 's4', 's5'],
  set: { ...none },
};

const answered = responseReturns(
  state('Got the answer', 'ready', 'Received 200 with the content'),
  'Response sent',
  'The adapter hands the response to the Lambda service, which sends it through the Function URL to the client.',
);

const startUp: Step[] = [
  containerCreated,
  {
    time: 'during start-up',
    heading: 'The app starts and loads its content',
    text: 'The adapter starts polling GET /health every 10 ms (limit 8 s). Meanwhile the app loads and validates content.public.json. A missing or invalid file aborts the start.',
    hi: ['s5', 'a'],
    set: {
      a: state('Polling', 'working', 'GET /health, limit 8 s'),
      s1: state('Starting', 'working', 'Server not listening yet'),
      s2: state('Starting', 'working', 'Server not listening yet'),
      s3: state('Starting', 'working', 'Server not listening yet'),
      s4: state('Starting', 'working', 'Server not listening yet'),
      s5: state('Loading', 'working', 'Reading content.public.json'),
    },
  },
  {
    time: 'a few seconds in',
    heading: 'The server starts listening',
    text: 'uvicorn listens on port 8080, the content sits in memory, and the layers are in place.',
    hi: ['s1', 's2', 's3', 's4', 's5'],
    set: ready,
  },
  {
    time: 'about 4 s in total',
    heading: 'The readiness check passes',
    text: 'GET /health gets 200 through the same layers. The adapter then starts the Lambda runtime client and begins forwarding events. Init is done. A cold start took about 4 s when measured on this project.',
    path: ['a', 's1', 's2', 's3', 's4', 's3', 's2', 's1', 'a'],
    hi: ['a', 's4', 'l'],
    set: {
      a: state('Ready', 'ready', 'Got 200, forwarding events'),
      l: state('Init done', 'ready', 'Waiting for the first event'),
    },
  },
];

const handling: Step[] = [adapterCalls, readOnlyAllows, corsAllows, routerAnswers, answerGoesUp];

export const SCENARIOS: Record<
  ScenarioKey,
  { name: string; initial: States; before: string; steps: Step[] }
> = {
  cold: {
    name: 'Cold start and request',
    initial: none,
    before: 'No container exists. Nothing is running and nothing is billed.',
    steps: [
      requestArrivesCold('GET', '/content'),
      ...startUp,
      adapterReceives('GET', '/content'),
      ...handling,
      answered,
      idleBetween,
      shutdown,
    ],
  },
  warm: {
    name: 'Warm request',
    initial: warm,
    before: 'A container from an earlier request is kept, with the adapter and the app ready.',
    steps: [requestArrivesWarm('GET', '/content'), ...handling, answered, idleBetween, shutdown],
  },
  post: {
    name: 'POST refused',
    initial: warm,
    before: 'A container from an earlier request is kept, with the adapter and the app ready.',
    steps: [
      requestArrivesWarm('POST', '/content'),
      adapterCalls,
      {
        time: 'request',
        heading: 'The read-only check refuses',
        text: 'POST is not GET or OPTIONS, so this layer answers 405 itself. CORS, the router and the content never see the request.',
        path: ['s1', 's2'],
        hi: ['s2'],
        set: { s2: state('Refused 405', 'error', 'Method not allowed') },
      },
      {
        time: 'request',
        heading: 'The 405 goes back up',
        text: 'The security layer still adds its headers to the refusal.',
        path: ['s2', 's1', 'a'],
        hi: ['s1', 'a'],
        set: {
          s1: state('Headers added', 'ready', 'Security headers on the 405'),
          a: state('Converting', 'working', 'Turns the 405 into a response event'),
        },
      },
      responseReturns(
        state('Got 405', 'ready', 'The request was refused'),
        '405 sent',
        'The client gets 405. The router and the content were never touched.',
      ),
      idleBetween,
    ],
  },
  fail: {
    name: 'Start-up failure',
    initial: none,
    before: 'No container exists. Nothing is running and nothing is billed.',
    steps: [
      requestArrivesCold('GET', '/content'),
      containerCreated,
      {
        time: 'during start-up',
        heading: 'The content is missing or invalid',
        text: 'During start-up the app loads and validates its content. If that fails, the start aborts and the server never listens. The adapter keeps polling.',
        hi: ['s5', 'a'],
        set: {
          s5: state('Invalid', 'error', 'Start-up aborts'),
          s1: state('Not started', 'idle', 'Server never listens'),
          s2: state('Not started', 'idle', 'Server never listens'),
          s3: state('Not started', 'idle', 'Server never listens'),
          s4: state('Not started', 'idle', 'Server never listens'),
          a: state('Polling', 'working', 'GET /health, limit 8 s'),
        },
      },
      {
        time: '8 s',
        heading: 'The adapter gives up',
        text: 'The readiness check never succeeds. After the 8 s limit set in the Dockerfile, the adapter fails instead of serving, and the runtime never starts.',
        hi: ['a'],
        set: { a: state('Gave up', 'error', 'Timeout after 8 s') },
      },
      {
        time: 'about 8 s',
        heading: 'The cold start fails',
        text: 'The client gets an error. This cannot reach production here: the image build runs the same content check first, so a broken file fails the build.',
        path: ['l', 'u', 'c'],
        hi: ['l', 'u', 'c'],
        set: {
          l: state('Init failed', 'error', 'The request gets an error'),
          u: state('Returned an error', 'error', 'The caller gets an error'),
          c: state('Got an error', 'error', 'The request failed'),
        },
      },
    ],
  },
};

/** The state of every component, and the Lambda phase, after `count` steps of a story. */
export function stateAfter(
  scenario: ScenarioKey,
  count: number,
): { states: States; phase: Phase | null } {
  const states: States = { ...SCENARIOS[scenario].initial };
  let phase: Phase | null = null;
  for (const step of SCENARIOS[scenario].steps.slice(0, count)) {
    Object.assign(states, step.set);
    if (step.phase) phase = step.phase;
    else phase ??= 'Invoke';
  }
  return { states, phase };
}
