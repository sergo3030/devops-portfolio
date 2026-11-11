import type { NodeId } from './architecture';

/**
 * The geometry of the station map. The request line has two layouts drawn from the same story data:
 * a wide one (a row along the top, the container box below on the right, short enough to sit next to
 * the controls on one screen) and a compact one for phones: one column, with each state pill on the
 * same row as its name and the container box below, so it is half as tall as a stacked drawing and
 * most of it fits on a phone screen beside the pinned controls. Coordinates are in SVG units, so
 * the map scales as a picture.
 *
 * Besides the nine components the stories talk about, the map has three places the request passes
 * through on the way: GitHub Pages, the content fork, and the container's front door (the dock).
 */
export type MapId = NodeId | 'p' | 'f' | 'k';
export type Point = readonly [number, number];
export type Variant = 'wide' | 'compact';

export const STEP_IDS = ['a', 's1', 's2', 's3', 's4', 's5'] as const;

export type Box = {
  x: number;
  y: number;
  w: number;
  h: number;
  /** Height of the title band at the top of the box. */
  head: number;
  /** Distance between two steps. */
  row: number;
  /** Where the first step's square starts. */
  first: number;
  /** The size of the numbered square. */
  sq: number;
  /** Whether each step's state pill sits on the same line as its name. */
  inline: boolean;
};

export type Layout = {
  size: Point;
  /** The request line, from the client to the container's front door. */
  main: Point[];
  /** Where the dot waits at each place. */
  pos: Record<MapId, Point>;
  box: Box;
  /** The grey branch from the fork to the saved copy, and the end of it. */
  saved: Point[];
};

function stepPositions(box: Box, centreX: number): Record<(typeof STEP_IDS)[number], Point> {
  const at = (index: number): Point => [centreX, box.first + index * box.row + box.sq / 2];
  return { a: at(0), s1: at(1), s2: at(2), s3: at(3), s4: at(4), s5: at(5) };
}

const wideBox: Box = {
  x: 940,
  y: 410,
  w: 540,
  h: 484,
  head: 100,
  row: 62,
  first: 520,
  sq: 48,
  inline: true,
};
const compactBox: Box = {
  x: 12,
  y: 408,
  w: 576,
  h: 484,
  head: 100,
  row: 62,
  first: 518,
  sq: 48,
  inline: true,
};

export const LAYOUTS: Record<Variant, Layout> = {
  wide: {
    size: [1500, 980],
    main: [
      [130, 200],
      [1000, 200],
      [1210, 410],
    ],
    pos: {
      c: [130, 200],
      p: [320, 200],
      f: [530, 200],
      u: [760, 200],
      l: [1000, 200],
      k: [1210, 410],
      ...stepPositions(wideBox, wideBox.x + 48),
    },
    box: wideBox,
    saved: [
      [530, 200],
      [430, 300],
    ],
  },
  compact: {
    size: [600, 904],
    main: [
      [36, 36],
      [36, 408],
    ],
    pos: {
      c: [36, 36],
      p: [36, 100],
      f: [36, 164],
      u: [36, 280],
      l: [36, 344],
      k: [36, 408],
      ...stepPositions(compactBox, compactBox.x + 48),
    },
    box: compactBox,
    saved: [
      [36, 164],
      [84, 222],
    ],
  },
};

/**
 * A story names only the nine components. On the map the request also passes GitHub Pages and the
 * fork between the client and the Function URL, and the container's front door between Lambda and
 * the adapter. This adds those stops, in the right order and in both directions.
 */
export function expandPath(path: readonly NodeId[]): MapId[] {
  const out: MapId[] = [];
  path.forEach((id, index) => {
    const before = path[index - 1];
    if (before === 'c' && id === 'u') out.push('p', 'f');
    else if (before === 'u' && id === 'c') out.push('f', 'p');
    else if (before === 'l' && id === 'a') out.push('k');
    else if (before === 'a' && id === 'l') out.push('k');
    out.push(id);
  });
  return out;
}

/** The width of a state pill: the label in the mono face at 22 units, plus padding. */
export function pillWidth(text: string): number {
  return Math.round(text.length * 13.2 + 26);
}
