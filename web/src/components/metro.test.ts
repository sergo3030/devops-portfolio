import { LAYOUTS, STEP_IDS } from './metro';

const VARIANTS = ['wide', 'compact'] as const;

describe('the map layouts', () => {
  for (const variant of VARIANTS) {
    it(`keep every stop of the ${variant} map inside its picture`, () => {
      const { size, pos, box, main, saved } = LAYOUTS[variant];
      for (const [x, y] of [...Object.values(pos), ...main, ...saved]) {
        expect(x).toBeGreaterThan(0);
        expect(x).toBeLessThan(size[0]);
        expect(y).toBeGreaterThan(0);
        expect(y).toBeLessThan(size[1]);
      }
      expect(box.x + box.w).toBeLessThanOrEqual(size[0]);
      expect(box.y + box.h).toBeLessThanOrEqual(size[1]);
    });

    it(`put the six steps of the ${variant} map inside the container box, one row apart`, () => {
      const { pos, box } = LAYOUTS[variant];
      STEP_IDS.forEach((id, index) => {
        const [x, y] = pos[id];
        expect(x - box.sq / 2).toBeGreaterThan(box.x);
        expect(y - box.sq / 2).toBeGreaterThan(box.y + box.head);
        expect(y + box.sq / 2).toBeLessThan(box.y + box.h);
        expect(y).toBe(box.first + index * box.row + box.sq / 2);
      });
    });

    it(`run the request line of the ${variant} map from the client to the front door`, () => {
      const { main, pos } = LAYOUTS[variant];
      expect(main[0]).toEqual(pos.c);
      expect(main[main.length - 1]).toEqual(pos.k);
    });
  }

  it('keeps the phone map close to a square, not a tall strip', () => {
    // the first phone drawing stacked the state pills under the names and was 460 x 1346 (1 : 2.9)
    const [width, height] = LAYOUTS.compact.size;
    expect(height / width).toBeLessThan(1.6);
  });
});
