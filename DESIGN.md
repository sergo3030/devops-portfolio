---
name: DevOps Portfolio
description: A warm circuit board. Greige board with a dot grid, raised modules lit from the top left, dark screens, keycaps, LEDs and printed traces, with one burnt-orange signal colour.
colors:
  board: "#d8d4ca"
  board-deep: "#cdc8bc"
  band: "#c9c4b7"
  panel-top: "#ebe7de"
  panel-bottom: "#dcd8ce"
  trace: "#b3ac9f"
  line: "#8f887b"
  ink: "#1c1b19"
  ink-muted: "#57524a"
  accent: "#d2682b"
  accent-strong: "#b4501a"
  on-accent: "#fff7ef"
  link: "#8f3f12"
  screen: "#1d1c1a"
  on-screen: "#ece8dc"
  board-night: "#1f1e1c"
  panel-top-night: "#33322e"
  panel-bottom-night: "#292825"
  ink-night: "#ece8dc"
  ink-muted-night: "#b2ac9f"
  accent-night: "#e8884a"
typography:
  display:
    fontFamily: "'Saira Semi Condensed', 'Arial Narrow', 'Segoe UI', sans-serif"
    fontSize: "clamp(3.25rem, 9vw, 5.75rem)"
    fontWeight: 700
    lineHeight: 0.92
  heading:
    fontFamily: "'Saira Semi Condensed', 'Arial Narrow', 'Segoe UI', sans-serif"
    fontSize: "clamp(2rem, 5vw, 2.5rem)"
    fontWeight: 700
    lineHeight: 1
  body:
    fontFamily: "'Figtree', system-ui, sans-serif"
    fontSize: "1rem"
    lineHeight: 1.6
  label:
    fontFamily: "'JetBrains Mono', ui-monospace, Consolas, monospace"
    fontSize: "0.75rem"
    fontWeight: 600
    letterSpacing: "0.09em"
rounded:
  device: "20px"
  module: "18px"
  key: "10px"
  small: "6px"
spacing:
  unit: "0.5rem"
  wall: "80rem"
---

# Design System: DevOps Portfolio

## Overview

**Creative North Star: "The warm circuit board."**
The page is one board. Everything on it is a part: a raised module, a dark screen, a keycap, an LED, a
printed trace. The look comes from a retro-computing landing page the owner chose, in warm greys, not
cool ones. It is professional but not boring: the hero is a device wired to skill modules, and a short
start-up plays once. The content is the owner's published text, unchanged.

Not this: neon dark developer templates, gradient text, a hero-metric row, nested cards, pastel
glassmorphism, or a decorative picture that carries no meaning.

## Colors

One accent on a restrained warm-grey board.

- **Board `#d8d4ca`** with a faint dot grid; modules go from `#ebe7de` to `#dcd8ce`.
- **Ink `#1c1b19`** for text; muted ink `#57524a` (4.5:1 or more on every surface).
- **Orange `#d2682b`** is a signal: LEDs, traces, the request, the working state. As a fill it is 2.5:1,
  so it never carries text. Text on an orange key uses `#b4501a` with `#fff7ef` (4.8:1).
- **Screens** are `#1d1c1a` with `#ece8dc` text.
- **Dark scheme:** warm charcoal board `#1f1e1c`, modules `#33322e` to `#292825`, text `#ece8dc`, orange
  lightened to `#e8884a` with dark ink on it.

## Typography

- **Saira Semi Condensed**, weight 700 only, for the name, headings, job titles and station names. Its
  squared curves echo the rounded-square modules and keys.
- **Figtree** for body text.
- **JetBrains Mono** for labels, dates, the skill keys, the screen and the state labels, at weights 500
  and 600, with 0.02em tracking. Labels are set in the case the text is written in, never in capitals.
- Outside the display face the weights are 400, 500 and 600.
- Fonts are self-hosted (the page's policy allows no other host).

## Elevation & Depth

Light comes from the top left. A module has a soft drop shadow, a white shadow on the lit side, and a
1 px highlight. A key is a smaller version and moves down 2 px when pressed. A well (the filter field,
a track) is the same shadow turned inward. Depth is the one effect. Every shadow is neutral: no hard offset shadows, no coloured shadows and no glows.

## Shapes

A panel is 14 to 20 px (modules 18, the device 20), a control 8 to 10 (keys 10, language sockets 12), a keycap or tag 4 to 6 (skill keys, phase chips and the screen 6), and an inner radius is the outer one minus the padding between them. Printed traces are 2 px lines. All spacing sits on a 4 px grid; a hero key is 44 px tall and a row key 36.

## Components

- **Device:** the hero module. Role and country as a printed label, the name on two lines, a screen with
  the summary and a cursor, two orange keys for the profiles, one size and 16 px apart.
- **Side modules:** up to six skill modules beside the device from 62rem, each with an LED that is
  off, and lit and softly pulsing while the content comes from the API (the same pulse as the status bar),
  three skills, a tick scale and a trace to the device. Decoration: hidden from assistive technology.
- **Keys:** page keys (the current page is pressed in, with a lit LED), orange profile keys, and the
  skills as small keycaps. A hidden skill leaves a dashed empty slot.
- **Job module:** a printed date line with an LED (off; lit and softly pulsing while the content comes
  from the API, like the skill modules'), the role in the display face, the bullets.
- **Language sockets:** a small module with the language name.
- **Section heading:** the heading with a printed trace running out to the edge.
- **Tab icon:** a keycap with a squared S and one orange LED, adapting to a dark browser theme.
- **Status bar:** a sticky printed label with an LED, lit and softly pulsing while the data is live, off when the saved copy is shown.
- **Architecture diagram:** the card is a module. Stories are keys, phases are mono chips, the controls
  are four keys on a dark screen with a grooved slider, and the map is a light trace in a groove with an
  orange signal. State is never colour alone: dashed outline, fill, cross, and the words. On a phone the
  controls are pinned at the top, the map has a compact layout, and the state table folds behind a key.

## Motion

One start-up: a boot screen (a logo and sixteen ticks) covers the page for 1.5 s and fades; the
modules rise 10 px in one after the other (60 ms apart, opacity and transform only), traces draw
themselves, the summary is revealed top to bottom, a short orange signal runs along each trace twice,
and the cursor starts to blink. Then the page is still, apart from the cursor and the live-data LEDs.
All of it is CSS.

One curve (`--ease`), a 150 ms press and a 500 ms entrance, all tokens. Nothing loops without a
reason: LEDs are steady, except the live-data LEDs (the status bar's, the skill modules' and the job modules'), which pulse softly while the data is live, and the hero's cursor, which blinks for as long as the page is open, as on a terminal. A lit LED
means something is live, current or working (the role line, the current page, live data, a working
step). Reduced motion removes the boot screen and every animation.
The diagram moves only when the visitor presses a key; its request line carries a signal twice when the
page opens and then rests.

## Do's and Don'ts

### Do:
- Keep text at WCAG AA contrast on every surface, in both schemes.
- Use orange for signals and for the main key only, with the deeper orange under text.
- Light an LED only where something is live, current or working.
- Take parts from `styles/parts.module.css` so a module, key or LED looks the same everywhere.
- Hide decoration from assistive technology and draw its words from data attributes.
- Let a component change a shared part through its custom property (`--key-padding`, `--module-radius` and the rest listed in `parts.module.css`), never by overriding the part's properties.

### Don't:
- Put text on the light orange `#d2682b`.
- Add an inline style (the Content-Security-Policy forbids it).
- Add a kicker above a heading, section numbers, nested cards, gradient text, uppercase tracked labels, glows or coloured shadows.
- Loop an animation that carries no meaning.
- Add public copy the owner has not approved (the start-up screen has no words on purpose).
