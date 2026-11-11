import { act, fireEvent, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ArchitectureDiagram } from './ArchitectureDiagram';
import { NODE_IDS, SCENARIOS, stateAfter, type ScenarioKey } from './architecture';

function preferReducedMotion(reduce: boolean) {
  Object.defineProperty(window, 'matchMedia', {
    configurable: true,
    value: () => ({
      matches: reduce,
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
    }),
  });
}

afterEach(() => {
  vi.useRealTimers();
  Reflect.deleteProperty(window, 'matchMedia');
});

const row = (name: string) => screen.getByRole('row', { name: new RegExp(name) });

describe('the stories', () => {
  it('start from a known state and carry each state forward', () => {
    expect(stateAfter('cold', 0).states.a.label).toBe('None');
    expect(stateAfter('cold', 0).phase).toBeNull();
    expect(stateAfter('cold', 1).phase).toBe('Init');
    expect(stateAfter('warm', 0).states.s4.label).toBe('Ready');
    // the first request step of a warm story is an invoke, even though no step names the phase
    expect(stateAfter('post', 1).phase).toBe('Invoke');
  });

  it('refuse the POST in the read-only layer and never touch the router', () => {
    const refused = stateAfter('post', 3).states;
    expect(refused.s2).toMatchObject({ label: 'Refused 405', tone: 'error' });
    expect(refused.s4.label).toBe('Ready');
  });

  it('end every story with only paths that name real components', () => {
    for (const key of Object.keys(SCENARIOS) as ScenarioKey[]) {
      for (const step of SCENARIOS[key].steps) {
        for (const id of [...(step.path ?? []), ...step.hi, ...Object.keys(step.set)]) {
          expect(NODE_IDS).toContain(id);
        }
      }
    }
  });
});

describe('the client end of the stories', () => {
  it('ends with the client holding the answer, a refusal, or an error', () => {
    const last = (key: ScenarioKey, from: number) =>
      stateAfter(key, SCENARIOS[key].steps.length - from).states.c;
    expect(last('warm', 2)).toMatchObject({ label: 'Got the answer', tone: 'ready' });
    expect(last('post', 1)).toMatchObject({ label: 'Got 405' });
    expect(stateAfter('fail', SCENARIOS.fail.steps.length).states.c).toMatchObject({
      label: 'Got an error',
      tone: 'error',
    });
  });

  it('sends every request from the client through the Function URL to Lambda', () => {
    for (const key of ['cold', 'warm', 'post', 'fail'] as const) {
      expect(SCENARIOS[key].steps[0]?.path?.slice(0, 3)).toEqual(['c', 'u', 'l']);
    }
  });
});

describe('ArchitectureDiagram', () => {
  it('offers the four stories and starts on the cold start, before the first step', () => {
    preferReducedMotion(true);
    render(<ArchitectureDiagram />);
    for (const name of [
      'Cold start and request',
      'Warm request',
      'POST refused',
      'Start-up failure',
    ]) {
      expect(screen.getByRole('button', { name })).toBeInTheDocument();
    }
    expect(screen.getByRole('button', { name: 'Cold start and request' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    expect(screen.getByText('Before the request')).toBeInTheDocument();
    expect(screen.getByText(/nothing is billed/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Back' })).toBeDisabled();
  });

  it('replays the current step without changing it', async () => {
    preferReducedMotion(true);
    const user = userEvent.setup();
    render(<ArchitectureDiagram />);
    expect(screen.getByRole('button', { name: 'Replay step' })).toBeDisabled();
    await user.click(screen.getByRole('button', { name: 'Next' }));
    await user.click(screen.getByRole('button', { name: 'Replay step' }));
    expect(screen.getByText('A request arrives')).toBeInTheDocument();
    expect(screen.getByRole('slider', { name: 'Step' })).toHaveValue('1');
  });

  it('restarts the story from any step, and is off at the start', async () => {
    preferReducedMotion(true);
    const user = userEvent.setup();
    render(<ArchitectureDiagram />);
    expect(screen.getByRole('button', { name: 'Restart' })).toBeDisabled();
    for (let i = 0; i < 4; i += 1) await user.click(screen.getByRole('button', { name: 'Next' }));
    expect(screen.getByRole('slider', { name: 'Step' })).toHaveValue('4');
    await user.click(screen.getByRole('button', { name: 'Restart' }));
    expect(screen.getByRole('slider', { name: 'Step' })).toHaveValue('0');
    expect(screen.getByText('Before the request')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Restart' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Back' })).toBeDisabled();
  });

  it('moves one step at a time, shows the Lambda phase, and stops at both ends', async () => {
    preferReducedMotion(true);
    const user = userEvent.setup();
    render(<ArchitectureDiagram />);
    await user.click(screen.getByRole('button', { name: 'Next' }));
    expect(screen.getByText('A request arrives')).toBeInTheDocument();
    expect(screen.getByText('Init', { selector: 'span' })).toHaveAttribute('aria-current', 'step');
    expect(within(row('Client')).getByText('Waiting for the answer')).toBeInTheDocument();
    expect(within(row('Function URL')).getByText('Received')).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Next' }));
    expect(screen.getByText('Lambda creates the container')).toBeInTheDocument();
    expect(within(row('Web Adapter')).getByText('Starting')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Back' }));

    await user.click(screen.getByRole('button', { name: 'Back' }));
    expect(screen.getByText('Before the request')).toBeInTheDocument();

    const total = SCENARIOS.cold.steps.length;
    for (let i = 0; i < total; i += 1)
      await user.click(screen.getByRole('button', { name: 'Next' }));
    expect(screen.getByText('Shutdown', { selector: 'p' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Next' })).toBeDisabled();
  });

  it('follows the slider, and the table says what each component is doing', () => {
    preferReducedMotion(true);
    render(<ArchitectureDiagram />);
    const slider = screen.getByRole('slider', { name: 'Step' });
    expect(slider).toHaveAttribute('max', String(SCENARIOS.cold.steps.length));
    fireEvent.change(slider, { target: { value: '5' } });
    expect(screen.getByText('The readiness check passes')).toBeInTheDocument();
    expect(
      within(row('Lambda service')).getByText('Waiting for the first event'),
    ).toBeInTheDocument();
    expect(
      within(row('Content in memory')).getByText('Loaded and validated at start'),
    ).toBeInTheDocument();
  });

  it('switches stories and starts the new one from the beginning', async () => {
    preferReducedMotion(true);
    const user = userEvent.setup();
    render(<ArchitectureDiagram />);
    await user.click(screen.getByRole('button', { name: 'Next' }));
    await user.click(screen.getByRole('button', { name: 'POST refused' }));
    expect(screen.getByRole('button', { name: 'POST refused' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    expect(screen.getByText('Before the request')).toBeInTheDocument();
    expect(screen.getByText(/container from an earlier request is kept/)).toBeInTheDocument();
    for (let i = 0; i < 3; i += 1) await user.click(screen.getByRole('button', { name: 'Next' }));
    expect(screen.getByText('The read-only check refuses')).toBeInTheDocument();
    expect(within(row('Read-only check')).getByText('Refused 405')).toBeInTheDocument();
  });

  it('has no play button and never moves by itself', () => {
    preferReducedMotion(false);
    vi.useFakeTimers();
    render(<ArchitectureDiagram />);
    expect(screen.queryByRole('button', { name: /^(Play|Pause)$/ })).not.toBeInTheDocument();
    act(() => {
      vi.advanceTimersByTime(60_000);
    });
    expect(screen.getByText('Before the request')).toBeInTheDocument();
    expect(screen.getByRole('slider', { name: 'Step' })).toHaveValue('0');
  });

  it('sends the request dot along the step on Next, and again on Replay', async () => {
    preferReducedMotion(false);
    const user = userEvent.setup();
    const { container } = render(<ArchitectureDiagram />);
    const dot = () => container.querySelector<SVGGElement>('g[class*="token"]');
    expect(dot()?.style.opacity ?? '').not.toBe('1');
    await user.click(screen.getByRole('button', { name: 'Next' }));
    expect(dot()?.style.opacity).toBe('1');
    // the slider and Back only show the step, without the dot
    const slider = screen.getByRole('slider', { name: 'Step' });
    fireEvent.change(slider, { target: { value: '2' } });
    fireEvent.change(slider, { target: { value: '1' } });
    expect(dot()?.style.opacity).toBe('0');
    await user.click(screen.getByRole('button', { name: 'Replay step' }));
    expect(dot()?.style.opacity).toBe('1');
  });

  it('keeps the dot hidden for a visitor who prefers reduced motion', async () => {
    preferReducedMotion(true);
    const user = userEvent.setup();
    const { container } = render(<ArchitectureDiagram />);
    await user.click(screen.getByRole('button', { name: 'Next' }));
    expect(container.querySelector<SVGGElement>('g[class*="token"]')?.style.opacity ?? '').not.toBe(
      '1',
    );
  });
});

describe('the pinned controls on a phone', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  /** jsdom has no layout, so the pinned bar and the lit step get fixed positions. */
  function onAPhone() {
    const scrollBy = vi.spyOn(window, 'scrollBy').mockImplementation(() => undefined);
    const real = window.getComputedStyle.bind(window);
    vi.spyOn(window, 'getComputedStyle').mockImplementation((element, pseudo) =>
      (element.getAttribute('class') ?? '').includes('dock')
        ? ({ position: 'sticky' } as CSSStyleDeclaration)
        : real(element, pseudo),
    );
    vi.spyOn(Element.prototype, 'getClientRects').mockReturnValue([{}] as unknown as DOMRectList);
    vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function (
      this: Element,
    ) {
      const lit = this.hasAttribute('data-node');
      const top = lit ? 900 : 0;
      const bottom = lit ? 960 : 260;
      return { top, bottom, left: 0, right: 0, width: 0, height: bottom - top } as DOMRect;
    });
    return scrollBy;
  }

  it('scrolls the page so the step that lights up is in view under the controls', async () => {
    preferReducedMotion(true);
    const scrollBy = onAPhone();
    const user = userEvent.setup();
    render(<ArchitectureDiagram />);
    expect(scrollBy).not.toHaveBeenCalled();
    await user.click(screen.getByRole('button', { name: 'Next' }));
    expect(scrollBy).toHaveBeenCalledTimes(1);
    // the open window is 272 to 712 (bar bottom plus a gap, to the status bar), the step is at 900 to 960
    expect(scrollBy).toHaveBeenCalledWith({ top: 438, behavior: 'auto' });
  });

  it('scrolls smoothly unless the visitor prefers reduced motion', async () => {
    preferReducedMotion(false);
    const scrollBy = onAPhone();
    const user = userEvent.setup();
    render(<ArchitectureDiagram />);
    await user.click(screen.getByRole('button', { name: 'Next' }));
    expect(scrollBy).toHaveBeenCalledWith(expect.objectContaining({ behavior: 'smooth' }));
  });

  it('does not scroll at the start of a story, or when the controls are not pinned', async () => {
    preferReducedMotion(true);
    const user = userEvent.setup();
    const scrollBy = vi.spyOn(window, 'scrollBy').mockImplementation(() => undefined);
    render(<ArchitectureDiagram />);
    // no layout engine, so the bar is not sticky: a laptop or desktop
    await user.click(screen.getByRole('button', { name: 'Next' }));
    expect(scrollBy).not.toHaveBeenCalled();
  });

  it('keeps every control and the step text inside the pinned bar', () => {
    preferReducedMotion(true);
    const { container } = render(<ArchitectureDiagram />);
    const dock = container.querySelector<HTMLElement>('[class*="dock"]');
    expect(dock).not.toBeNull();
    const bar = within(dock as HTMLElement);
    for (const name of ['Restart', 'Back', 'Replay step', 'Next']) {
      expect(bar.getByRole('button', { name })).toBeInTheDocument();
    }
    expect(bar.getByRole('slider', { name: 'Step' })).toBeInTheDocument();
    expect(bar.getByText('Before the request')).toBeInTheDocument();
  });
});
