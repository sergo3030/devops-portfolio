import { scrollToShow } from './follow';

// The open window sits between the pinned controls (bottom edge at 280) and the status bar (600).
const view = { top: 280, bottom: 600 };

describe('scrollToShow', () => {
  it('leaves the page alone when the lit part is well inside the window', () => {
    expect(scrollToShow({ top: 350, bottom: 450 }, view)).toBe(0);
  });

  it('scrolls down to centre a lit part below the window', () => {
    expect(scrollToShow({ top: 700, bottom: 800 }, view)).toBe(310);
  });

  it('scrolls up to centre a lit part that is hidden under the pinned controls', () => {
    expect(scrollToShow({ top: 100, bottom: 200 }, view)).toBe(-290);
  });

  it('treats a part hugging an edge as out of place, so the next step is not cut off', () => {
    expect(scrollToShow({ top: 285, bottom: 330 }, view)).toBeLessThan(0);
    expect(scrollToShow({ top: 540, bottom: 595 }, view)).toBeGreaterThan(0);
  });

  it('lines the top up under the controls when the lit part is taller than the window', () => {
    expect(scrollToShow({ top: 400, bottom: 800 }, view)).toBe(112);
    // and stays put once it is there
    expect(scrollToShow({ top: 288, bottom: 688 }, view)).toBe(0);
  });

  it('does nothing when there is no open window', () => {
    expect(scrollToShow({ top: 0, bottom: 10 }, { top: 500, bottom: 480 })).toBe(0);
  });
});
