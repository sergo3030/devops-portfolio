/** A vertical span on the screen, in pixels from the top of the viewport. */
export type Span = { top: number; bottom: number };

/** The gap kept under the pinned controls when a step has to be lined up with the top. */
const LEAD = 8;

/** How much of the open window, at each end, counts as "too close to the edge". */
const EDGE = 0.15;

/**
 * How far to scroll (positive is down) so the lit part of the map sits in the open window: the
 * space between the pinned controls and the foot of the screen. It returns 0 when the lit part is
 * already well inside, so stepping through a story that stays on screen never scrolls the page.
 * Otherwise it centres the lit part, or lines its top up under the controls when it is taller than
 * the window.
 */
export function scrollToShow(lit: Span, view: Span): number {
  const room = view.bottom - view.top;
  const size = lit.bottom - lit.top;
  if (room <= 0) return 0;
  if (size > room) return lit.top - (view.top + LEAD);
  const safeTop = view.top + room * EDGE;
  const safeBottom = view.bottom - room * EDGE;
  if (lit.top >= safeTop && lit.bottom <= safeBottom) return 0;
  return (lit.top + lit.bottom) / 2 - (view.top + view.bottom) / 2;
}
