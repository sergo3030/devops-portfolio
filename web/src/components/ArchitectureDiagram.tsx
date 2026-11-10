import { useCallback, useEffect, useId, useRef, useState, type ReactNode } from 'react';
import styles from './ArchitectureDiagram.module.css';
import {
  NODE_IDS,
  NODE_NAMES,
  PHASES,
  SCENARIOS,
  stateAfter,
  type NodeId,
  type ScenarioKey,
  type States,
} from './architecture';
import {
  expandPath,
  LAYOUTS,
  pillWidth,
  STEP_IDS,
  type Layout,
  type MapId,
  type Point,
  type Variant,
} from './metro';

/** How long the dot takes to hop from one place to the next. */
const HOP_MS = 430;

const SCENARIO_KEYS = Object.keys(SCENARIOS) as ScenarioKey[];
const VARIANTS: Variant[] = ['wide', 'tall'];
const TONES = [
  ['idle', 'Not running'],
  ['ready', 'Ready'],
  ['working', 'Working'],
  ['error', 'Error'],
] as const;
const TOP_ROW = ['c', 'u', 'l'] as const;

function prefersReducedMotion(): boolean {
  return (
    typeof window.matchMedia === 'function' &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches
  );
}

/** The player icons: restart, previous, next and replay. They are drawn, so no icon font is needed. */
function Icon({ kind }: { kind: 'restart' | 'back' | 'next' | 'replay' }) {
  return (
    <svg className={styles.icon} viewBox="0 0 24 24" focusable="false" aria-hidden="true">
      {kind === 'restart' ? (
        <>
          <rect x="3" y="5" width="3" height="14" fill="currentColor" />
          <path d="M13 5v14L5.5 12z" fill="currentColor" />
          <path d="M21 5v14l-7.5-7z" fill="currentColor" />
        </>
      ) : kind === 'replay' ? (
        <>
          <path
            d="M19 12a7 7 0 1 1-2.05-4.95"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.5"
          />
          <path d="M21 3.5V10h-6.5z" fill="currentColor" />
        </>
      ) : kind === 'back' ? (
        <>
          <rect x="5" y="5" width="3" height="14" fill="currentColor" />
          <path d="M19 5v14L9 12z" fill="currentColor" />
        </>
      ) : (
        <>
          <rect x="16" y="5" width="3" height="14" fill="currentColor" />
          <path d="M5 5v14l10-7z" fill="currentColor" />
        </>
      )}
    </svg>
  );
}

/** The request itself: a small envelope in a round badge that tilts and sends out a ring. */
function Token({ tokenRef }: { tokenRef: (element: SVGGElement | null) => void }) {
  return (
    <g ref={tokenRef} className={styles.token}>
      <circle className={styles.tokenRing} r="30" />
      <circle className={styles.tokenBody} r="22" />
      <g className={styles.tokenIcon}>
        <g transform="translate(-12 -12)">
          <rect
            x="3"
            y="5"
            width="18"
            height="14"
            rx="2"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
          />
          <path
            d="M3.5 6.5 12 13l8.5-6.5"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinejoin="round"
          />
        </g>
      </g>
    </g>
  );
}

const points = (list: readonly Point[]) =>
  list.map(([x, y]) => `${String(x)},${String(y)}`).join(' ');

const PILL_H = 36;

function boxLeft(x: number, width: number, anchor: 'start' | 'middle' | 'end'): number {
  if (anchor === 'middle') return x - width / 2;
  if (anchor === 'end') return x - width;
  return x;
}

function Pill({
  x,
  y,
  text,
  tone,
  anchor,
}: {
  x: number;
  y: number;
  text: string;
  tone: string;
  anchor: 'start' | 'middle' | 'end';
}) {
  const width = pillWidth(text);
  const left = boxLeft(x, width, anchor);
  return (
    <g className={`${styles.pill} ${styles[tone]}`}>
      <rect x={left} y={y} width={width} height={PILL_H} rx={6} />
      <text x={left + width / 2} y={y + 26} textAnchor="middle">
        {text}
      </text>
    </g>
  );
}

/** A small fixed tag, for the stops that have no state. */
function Tag({
  x,
  y,
  text,
  anchor = 'start',
}: {
  x: number;
  y: number;
  text: string;
  anchor?: 'start' | 'middle' | 'end';
}) {
  const width = pillWidth(text);
  const left = boxLeft(x, width, anchor);
  return (
    <g className={styles.tag}>
      <rect x={left} y={y} width={width} height={PILL_H} rx={6} />
      <text x={left + width / 2} y={y + 26} textAnchor="middle">
        {text}
      </text>
    </g>
  );
}

function Ring({ at, tone, lit }: { at: Point; tone?: string; lit?: boolean }) {
  const [x, y] = at;
  return (
    <>
      {lit ? <circle className={styles.halo} cx={x} cy={y} r={32} /> : null}
      <circle
        className={`${styles.ring} ${tone ? styles[tone] : styles.still}`}
        cx={x}
        cy={y}
        r={19}
      />
      {tone === 'error' ? (
        <path
          className={styles.cross}
          d={`M${String(x - 7)} ${String(y - 7)}L${String(x + 7)} ${String(y + 7)}M${String(x + 7)} ${String(y - 7)}L${String(x - 7)} ${String(y + 7)}`}
        />
      ) : (
        <circle className={styles.core} cx={x} cy={y} r={6} />
      )}
    </>
  );
}

type MapProps = {
  variant: Variant;
  states: States;
  lit: NodeId[];
  tokenRef: (element: SVGGElement | null) => void;
};

const NOTE = [
  'Pages always serves',
  'the site first. Then',
  'the page asks the',
  'API for live content.',
  'If that fails, the',
  'saved copy stays.',
];
const SITE_STOPS: [number, string][] = [
  [430, 'Pages workflow'],
  [520, 'Merge to main'],
];
const DEPLOY_STOPS: [number, string][] = [
  [450, 'tofu apply (deploy)'],
  [560, 'OIDC role, no stored keys'],
  [650, 'ECR image'],
  [740, 'Image build'],
  [830, 'Release tag'],
];

/** The station map. It is a picture: the table below it says the same in words. */
function StationMap({ variant, states, lit, tokenRef }: MapProps) {
  const layout: Layout = LAYOUTS[variant];
  const wide = variant === 'wide';
  const { pos, box } = layout;
  const [width, height] = layout.size;
  const on = (id: NodeId) => lit.includes(id);

  const stationNode = (id: (typeof TOP_ROW)[number]): ReactNode => {
    const [x, y] = pos[id];
    const state = states[id];
    return (
      <g key={id} data-node={id}>
        <Ring at={pos[id]} tone={state.tone} lit={on(id)} />
        {wide ? (
          <>
            <text className={styles.name} x={x} y={y - 38} textAnchor="middle">
              {NODE_NAMES[id]}
            </text>
            <Pill
              x={id === 'c' ? 10 : x}
              y={y - 104}
              text={state.label}
              tone={state.tone}
              anchor={id === 'c' ? 'start' : 'middle'}
            />
          </>
        ) : (
          <>
            <text className={styles.name} x={x + 34} y={y - 2}>
              {NODE_NAMES[id]}
            </text>
            <Pill x={x + 34} y={y + 8} text={state.label} tone={state.tone} anchor="start" />
          </>
        )}
      </g>
    );
  };

  const [fx, fy] = pos.f;
  const [px, py] = pos.p;
  const [sx, sy] = layout.saved[1] ?? pos.f;
  const rowX = box.x + 24;
  const textX = wide ? rowX : rowX + 36;
  const headerPath = `M${String(box.x)} ${String(box.y + box.head)}V${String(box.y + 8)}a8 8 0 0 1 8-8h${String(box.w - 16)}a8 8 0 0 1 8 8V${String(box.y + box.head)}z`;
  const boxCentre = box.x + box.w / 2;

  return (
    <svg
      className={`${styles.svg} ${wide ? styles.wide : styles.tall}`}
      viewBox={`0 0 ${String(width)} ${String(height)}`}
      aria-hidden="true"
      focusable="false"
    >
      {/* the grey lines: where the request is not going */}
      <polyline className={styles.grey} points={points(layout.saved)} />
      {wide ? (
        <>
          <polyline className={styles.grey} points="320,200 320,520" />
          <polyline className={styles.grey} points="760,200 880,320 880,830" />
          <polyline className={styles.grey} points="1000,200 880,320" />
          <polyline
            className={styles.grey}
            points={`${String(boxCentre)},${String(box.y + box.h)} ${String(boxCentre)},940`}
          />
        </>
      ) : null}

      {/* the request line */}
      <polyline className={styles.lineOutline} points={points(layout.main)} />
      <polyline className={styles.line} points={points(layout.main)} />
      <polyline className={styles.pulse} pathLength={1} points={points(layout.main)} />

      {/* GitHub Pages, then the fork: the site is always served first */}
      <Ring at={pos.p} />
      <polygon
        className={styles.fork}
        points={`${String(fx)},${String(fy - 24)} ${String(fx + 24)},${String(fy)} ${String(fx)},${String(fy + 24)} ${String(fx - 24)},${String(fy)}`}
      />
      <circle className={styles.ringGrey} cx={sx} cy={sy} r={10} />
      {wide ? (
        <>
          <text className={styles.name} x={px} y={py - 38} textAnchor="middle">
            GitHub Pages
          </text>
          <Tag x={px} y={py + 30} text="static files" anchor="middle" />
          <text className={styles.name} x={fx} y={fy - 38} textAnchor="middle">
            Content fork
          </text>
          <Tag x={fx} y={fy - 104} text="live: API call" anchor="middle" />
          <text className={styles.label} x={sx + 28} y={sy + 6}>
            Saved copy, if the
          </text>
          <text className={styles.label} x={sx + 28} y={sy + 36}>
            API is offline
          </text>
        </>
      ) : (
        <>
          <text className={styles.name} x={px + 34} y={py - 2}>
            GitHub Pages
          </text>
          <Tag x={px + 34} y={py + 8} text="static files" />
          <text className={styles.name} x={fx + 34} y={fy - 4}>
            Content fork
          </text>
          <Tag x={fx + 70} y={fy + 6} text="live: calls the API" />
          <text className={styles.label} x={sx + 26} y={sy + 2}>
            Saved copy,
          </text>
          <text className={styles.label} x={sx + 26} y={sy + 30}>
            if the API is offline
          </text>
        </>
      )}

      {TOP_ROW.map(stationNode)}

      {wide ? (
        <>
          {/* the lines around the request path: the site, the deploy, the logs, the cost alerts */}
          {SITE_STOPS.map(([y, text]) => (
            <g key={text}>
              <circle className={styles.ringGrey} cx={320} cy={y} r={10} />
              <text className={styles.label} x={350} y={y + 8}>
                {text}
              </text>
            </g>
          ))}
          {DEPLOY_STOPS.map(([y, text]) => (
            <g key={text}>
              <circle className={styles.ringGrey} cx={880} cy={y} r={10} />
              <text className={styles.label} x={850} y={y + 8} textAnchor="end">
                {text}
              </text>
            </g>
          ))}
          <circle className={styles.ringGrey} cx={boxCentre} cy={940} r={10} />
          <text className={styles.label} x={boxCentre - 30} y={948} textAnchor="end">
            CloudWatch Logs
          </text>
          {NOTE.map((line, index) => (
            <text key={line} className={styles.label} x={30} y={330 + index * 34}>
              {line}
            </text>
          ))}
          <rect className={styles.cost} x={1190} y={30} width={290} height={124} rx={8} />
          <text className={styles.costTitle} x={1214} y={66}>
            Cost guard
          </text>
          <text className={styles.label} x={1214} y={100}>
            Budget alert
          </text>
          <text className={styles.label} x={1214} y={132}>
            Cost anomaly alert
          </text>
        </>
      ) : null}

      {/* the container: one stop on the line, with the steps inside it */}
      <g>
        <rect className={styles.box} x={box.x} y={box.y} width={box.w} height={box.h} rx={8} />
        <path className={styles.boxHead} d={headerPath} />
        <text className={styles.boxTitle} x={textX} y={box.y + box.head * 0.6}>
          Lambda container
        </text>
        <text className={styles.boxSub} x={textX} y={box.y + box.head - 12}>
          Web Adapter + FastAPI, port 8080
        </text>
        {STEP_IDS.map((id, index) => {
          const [cx, cy] = pos[id];
          const top = cy - box.sq / 2;
          const state = states[id];
          return (
            <g key={id} data-node={id}>
              {index > 0 ? (
                <line
                  className={styles.stem}
                  x1={cx}
                  y1={top - box.row + box.sq}
                  x2={cx}
                  y2={top}
                />
              ) : null}
              <rect
                className={`${styles.step} ${styles[state.tone]} ${on(id) ? styles.stepLit : ''}`}
                x={cx - box.sq / 2}
                y={top}
                width={box.sq}
                height={box.sq}
                rx={6}
              />
              <text className={styles.stepNumber} x={cx} y={top + box.sq * 0.7} textAnchor="middle">
                {index + 1}
              </text>
              <text
                className={styles.stepName}
                x={cx + box.sq / 2 + 16}
                y={box.inline ? top + box.sq * 0.7 : top + 22}
              >
                {NODE_NAMES[id]}
              </text>
              {box.inline ? (
                <Pill
                  x={box.x + box.w - 22}
                  y={top + (box.sq - PILL_H) / 2}
                  text={state.label}
                  tone={state.tone}
                  anchor="end"
                />
              ) : (
                <Pill
                  x={cx + box.sq / 2 + 16}
                  y={top + 30}
                  text={state.label}
                  tone={state.tone}
                  anchor="start"
                />
              )}
            </g>
          );
        })}
      </g>
      <Ring at={pos.k} />

      <Token tokenRef={tokenRef} />
    </svg>
  );
}

/**
 * An animated picture of what happens from the visitor's browser to the code inside the Lambda
 * container, one step at a time, drawn as a station map. The visitor picks a story and steps
 * through it with Next and Back or the slider; nothing moves by itself. Next (and Replay) send the
 * dot along the path of the step, and the dot is skipped for a visitor who prefers reduced motion.
 * The dot is moved through the element's style object (not a style attribute in the markup), which
 * the page's Content-Security-Policy allows.
 */
export function ArchitectureDiagram() {
  const sliderId = useId();
  const [scenario, setScenario] = useState<ScenarioKey>('cold');
  const [step, setStep] = useState(0);

  const scenarioRef = useRef<ScenarioKey>('cold');
  const stepRef = useRef(0);
  const tokens = useRef<Record<Variant, SVGGElement | null>>({ wide: null, tall: null });
  const timers = useRef<{ hops: number[] }>({ hops: [] });

  const clearHops = useCallback(() => {
    timers.current.hops.forEach((id) => {
      window.clearTimeout(id);
    });
    timers.current.hops = [];
  }, []);

  const hideDot = useCallback(() => {
    clearHops();
    for (const variant of VARIANTS) {
      const token = tokens.current[variant];
      if (token) token.style.opacity = '0';
    }
  }, [clearHops]);

  const moveTo = useCallback((id: MapId) => {
    for (const variant of VARIANTS) {
      const token = tokens.current[variant];
      const [x, y] = LAYOUTS[variant].pos[id];
      if (token) token.style.transform = `translate(${String(x)}px, ${String(y)}px)`;
    }
  }, []);

  const fly = useCallback(
    (path: NodeId[]) => {
      const stops = expandPath(path);
      const start = stops[0];
      if (start === undefined || prefersReducedMotion()) return;
      clearHops();
      for (const variant of VARIANTS) {
        const token = tokens.current[variant];
        if (!token) continue;
        token.style.transition = 'none';
        token.style.opacity = '1';
      }
      moveTo(start);
      for (const variant of VARIANTS) {
        const token = tokens.current[variant];
        if (!token) continue;
        void token.getBoundingClientRect();
        token.style.transition = '';
      }
      stops.slice(1).forEach((id, index) => {
        timers.current.hops.push(
          window.setTimeout(
            () => {
              moveTo(id);
            },
            40 + index * HOP_MS,
          ),
        );
      });
      timers.current.hops.push(
        window.setTimeout(
          () => {
            for (const variant of VARIANTS) {
              const token = tokens.current[variant];
              if (token) token.style.opacity = '0';
            }
          },
          40 + stops.length * HOP_MS,
        ),
      );
    },
    [clearHops, moveTo],
  );

  const show = useCallback(
    (index: number, animate: boolean) => {
      stepRef.current = index;
      setStep(index);
      const path = SCENARIOS[scenarioRef.current].steps[index - 1]?.path;
      if (animate && path) fly(path);
      else hideDot();
    },
    [fly, hideDot],
  );

  useEffect(() => {
    const running = timers.current;
    return () => {
      running.hops.forEach((id) => {
        window.clearTimeout(id);
      });
    };
  }, []);

  const story = SCENARIOS[scenario];
  const { states, phase } = stateAfter(scenario, step);
  const current = step > 0 ? story.steps[step - 1] : undefined;
  const lit = current?.hi ?? [];

  const choose = (key: ScenarioKey) => {
    scenarioRef.current = key;
    setScenario(key);
    show(0, false);
  };

  return (
    <div className={styles.panel}>
      <div className={styles.scenarios} role="group" aria-label="Scenario">
        {SCENARIO_KEYS.map((key) => (
          <button
            key={key}
            type="button"
            className={styles.scenario}
            aria-pressed={scenario === key}
            onClick={() => {
              choose(key);
            }}
          >
            {SCENARIOS[key].name}
          </button>
        ))}
      </div>

      <div className={styles.phases}>
        <span className={styles.phasesLabel}>Lambda phase</span>
        {PHASES.map((name) => (
          <span
            key={name}
            className={phase === name ? styles.phaseOn : styles.phase}
            aria-current={phase === name ? 'step' : undefined}
          >
            {name}
          </span>
        ))}
      </div>

      <div className={styles.map}>
        <div className={styles.side}>
          <div className={styles.controls}>
            <div className={styles.player} role="group" aria-label="Steps">
              <button
                type="button"
                className={styles.transport}
                aria-label="Restart"
                title="Back to the start of the story"
                disabled={step === 0}
                onClick={() => {
                  show(0, false);
                }}
              >
                <Icon kind="restart" />
              </button>
              <button
                type="button"
                className={styles.transport}
                aria-label="Back"
                title="Back one step"
                disabled={step === 0}
                onClick={() => {
                  show(step - 1, false);
                }}
              >
                <Icon kind="back" />
              </button>
              <button
                type="button"
                className={styles.transport}
                aria-label="Replay step"
                title="Replay this step"
                disabled={step === 0}
                onClick={() => {
                  show(step, true);
                }}
              >
                <Icon kind="replay" />
              </button>
              <button
                type="button"
                className={`${styles.transport} ${styles.transportMain}`}
                aria-label="Next"
                title="Next step"
                disabled={step === story.steps.length}
                onClick={() => {
                  show(step + 1, true);
                }}
              >
                <Icon kind="next" />
              </button>
            </div>
            <input
              id={sliderId}
              className={styles.slider}
              type="range"
              min={0}
              max={story.steps.length}
              step={1}
              value={step}
              aria-label="Step"
              aria-valuetext={`Step ${String(step)} of ${String(story.steps.length)}`}
              onChange={(event) => {
                show(Number(event.target.value), false);
              }}
            />
            <span className={styles.time}>{current ? current.time : 'start'}</span>
          </div>

          <div className={styles.caption} aria-live="polite">
            <p className={styles.heading}>{current ? current.heading : 'Before the request'}</p>
            <p className={styles.text}>{current ? current.text : story.before}</p>
          </div>

          <ul className={styles.legend} aria-label="What the colours mean">
            {TONES.map(([tone, name]) => (
              <li key={tone}>
                <span className={`${styles.rowDot} ${styles[tone]}`} aria-hidden="true" />
                {name}
              </li>
            ))}
          </ul>
        </div>

        {VARIANTS.map((variant) => (
          <StationMap
            key={variant}
            variant={variant}
            states={states}
            lit={lit}
            tokenRef={(element) => {
              tokens.current[variant] = element;
            }}
          />
        ))}

        <ul className={styles.around} aria-label="Around the request path">
          <li>Site: merge to main, Pages workflow, GitHub Pages.</li>
          <li>
            Deploy: release tag, image build, ECR image, OIDC role with no stored keys, tofu apply.
            It creates both the Function URL and the Lambda.
          </li>
          <li>Logs: CloudWatch Logs. Cost guard: a budget alert and a cost anomaly alert.</li>
        </ul>
      </div>

      <table className={styles.table}>
        <caption className={styles.tableCaption}>State of each component</caption>
        <thead className={styles.tableHead}>
          <tr>
            <th scope="col">Component</th>
            <th scope="col">State</th>
            <th scope="col">What it is doing</th>
          </tr>
        </thead>
        <tbody>
          {NODE_IDS.map((id) => {
            const row = states[id];
            return (
              <tr key={id}>
                <th scope="row" className={styles.rowName}>
                  <span className={`${styles.rowDot} ${styles[row.tone]}`} />
                  {NODE_NAMES[id]}
                </th>
                <td>{row.label}</td>
                <td className={styles.detail}>{row.detail}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
