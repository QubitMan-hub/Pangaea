# Design: the living atlas

Pangaea should feel like opening a beautifully made atlas that happens to be alive. It should not
feel like a SaaS dashboard. The map is the product; interface chrome is a few precise instruments
floating over it. Every rule here is free to ship: system and open-source fonts served as static
files, CSS, and our own rendering. Nothing adds recurring cost.

Status: **direction for review.** Values are implemented as tokens in `src/app/globals.css`, and
screens follow this document. The palette numbers were validated with the data-visualization
skill's palette validator (OKLab color-vision checks) and a WCAG contrast check.

## 1. Identity

**Metaphor:** a hand-made atlas of human ideas. Regions are lands, the space between them is open
sea, and plots are parcels of land. Zoomed out, the world reads as a map you'd frame; zoomed in, it
becomes a living notebook.

**Signature details** (the things that make a screenshot recognizably Pangaea):

1. **Coastlines.** Region outlines are traced from their grid cells and smoothed (Chaikin), drawn as
   a 1.5 px ink-colored hairline with a soft inner wash of the region color. They look hand-inked,
   not like boxes.
2. **Lettering.** Labels follow chart and topographic-map lettering, not book typography.
   Continent names are wide-tracked capitals in IBM Plex Sans Condensed; region names are Plex Sans
   italic, the way charts letter features. Labels sit on the land and never wear the region color;
   they are ink.
3. **Graticule.** A faint latitude/longitude grid in the sea. It fades out as you zoom in, so you
   always feel the scale of the world.
4. **Chart by day, night chart after dark.** Nautical-chart color conventions: cool pale water,
   warm buff land tinted per region, precise ink lines. The dark theme is a night chart, with a deep
   navy sea and land that glows slightly. Deliberately not the cream-paper, serif and terracotta look
   that generic AI design defaults to.
5. **Instruments, not toolbars.** Zoom and compass control, scale bar ("100 plots"), inset minimap
   and the "wander" die are drawn like cartographic instruments: round, ink-lined, precise.
6. **"You are here."** Your own plot carries a small ink pin with a soft pulse, the one animated
   thing on a still map.

**Not this:** gray app background, rows of white cards, gradient blobs, glassmorphism everywhere,
generic geometric sans in all caps, or the cream-paper-with-serif-display cliché.

## 2. Color

All colors are tokens. Text always wears text tokens, never a region color.

### 2.1 Surfaces and ink

| Token       | Light (day chart) | Dark (night chart) | Use                                                   |
| ----------- | ----------------- | ------------------ | ----------------------------------------------------- |
| `--sea`     | `#e3eaec`         | `#0b1720`          | Page and map background (open water)                  |
| `--land`    | `#f1ead6`         | `#1d2620`          | Base that region washes are mixed into                |
| `--sheet`   | `#f7f9f9`         | `#13232e`          | Bottom sheets, palette, dialogs                       |
| `--ink`     | `#15202a`         | `#e6edef`          | Primary text and coastlines. 13.6:1 / 15.3:1 on sea   |
| `--ink-2`   | `#44515c`         | `#b3c0c6`          | Secondary text. 6.7:1 / 9.7:1                         |
| `--ink-3`   | `#5b6873`         | `#8e9ca3`          | Muted text and captions. 4.7:1 / 6.4:1 (AA)           |
| `--line`    | `#c3cfd3`         | `#24384a`          | Hairlines, graticule, dividers (decorative)           |
| `--accent`  | `#0f5f86`         | `#7cc0e8`          | Links, focus ring, selection. 5.8:1 / 9.1:1           |
| `--success` | `#2a6b45`         | `#7cc79a`          | Approved. Always with an icon and a label             |
| `--warning` | `#855000`         | `#e0a54a`          | In review. Always with an icon and a label            |
| `--danger`  | `#ad2a20`         | `#f08a80`          | Blocked, destructive. Always with an icon and a label |

All text tokens clear WCAG AA (4.5:1) on both `--sea` and `--sheet` in both themes.

Primary buttons are **ink-filled** (ink background, sea-colored text), like a stamp. Accent blue is
for links, focus and selection only, so it never competes with region colors. Status colors are
reserved and never used as region colors.

### 2.2 Region palette (8 hues, adjacency-aware)

Each region gets one hue for life ("color follows the entity"). It has two roles:

- **Land fill:** a wash of the hue mixed into `--land` (26% light, 30% dark).
- **Plot blocks and outline accents:** the full hue.

| Slot | Hue        | Light     | Dark      | Land wash light / dark |
| ---- | ---------- | --------- | --------- | ---------------------- |
| 1    | terracotta | `#c8553d` | `#e06a4f` | `#e6c3ae` / `#583a2e`  |
| 2    | lagoon     | `#0a8fb0` | `#22a6c4` | `#b5d2cc` / `#1e4c51`  |
| 3    | ochre      | `#bf8a14` | `#d9a23a` | `#e4d1a4` / `#554b28`  |
| 4    | plum       | `#9a46a8` | `#b46ac2` | `#dabfca` / `#4a3a51`  |
| 5    | moss       | `#4f9a3a` | `#6bb356` | `#c7d5ad` / `#345030`  |
| 6    | indigo     | `#5a4fc4` | `#7d74e0` | `#cac2d1` / `#3a3d5a`  |
| 7    | rose       | `#d0517f` | `#e06a95` | `#e8c2bf` / `#583a43`  |
| 8    | cobalt     | `#2f6fd0` | `#4f8ae6` | `#bfcad4` / `#2c445b`  |

**Validation** (palette validator, OKLab ×100, Machado color-vision simulation):

- **Light** (sea `#e3eaec`):
  - chroma floor and normal-vision separation pass
  - adjacent colorblind ΔE at least 13.2 (target 8)
  - ochre (2.5:1) and moss (2.9:1) marks are under 3:1 against the water, which is allowed
    because every region is directly labelled and outlined in ink
- **Dark** (sea `#0b1720`): every check passes, with all hues at 3:1 or better.
- **Ink labels on any land wash:** 9.6–11.0:1 light and 7.3–8.9:1 dark.
- Land is set apart from water by the ink coastline (13.6:1), not by fill contrast.

**Why 8 hues and not one per region:** no palette keeps more than about 8 hues distinguishable
across every pair for colorblind readers. A map only needs **neighbors** to differ, so regions are
colored with an adjacency-aware greedy coloring that only lets these pairs touch (both themes
checked, colorblind ΔE ≥ 8 and normal ≥ 15):

```
allowed neighbors: 1:{2,4,6,8}  2:{1,3,5,6,7}  3:{2,4,6,7,8}  4:{1,3,5}
                   5:{2,4,6,8}  6:{1,2,3,5,7}  7:{2,3,6,8}    8:{1,3,5,7}
```

If no allowed slot is free (rare on a planar map), the farthest-separated slot is used. That's fine,
because identity never rests on color alone: every region has its coastline and its label.
Continents tint their regions' coastlines slightly darker, to read as one landmass.

### 2.3 Themes

Light and dark are both designed, not inverted. The default follows the system setting, and a
toggle overrides it (`data-theme`). The map, thumbnails' frames and region washes all switch
together. Thumbnails themselves are user content and are never recolored.

## 3. Typography

| Role                | Family                                           | Notes                                       |
| ------------------- | ------------------------------------------------ | ------------------------------------------- |
| Continent labels    | **IBM Plex Sans Condensed** SemiBold             | Capitals, tracking +0.22em, chart-style     |
| Region labels       | **IBM Plex Sans** Italic, Medium                 | The chart convention for named features     |
| Headlines           | **IBM Plex Sans Condensed** SemiBold             | Tight, technical, confident                 |
| UI and body         | **IBM Plex Sans** + **IBM Plex Sans Devanagari** | Hindi with the same voice, no fallback jump |
| Code cards, figures | **IBM Plex Mono**                                | Coordinates, counts, code                   |

One superfamily gives the whole product a single, instrument-like voice. All are open-source (SIL
Open Font License), self-hosted through `next/font` at build time and served as static files, so
they're free. Only the weights we use are subset. Tracking and capitals apply to Latin scripts only;
Devanagari labels use Plex Sans Devanagari at the same weights.

**Scale** (rem, 16 px root, about ×1.25): 0.75 · 0.875 · 1 · 1.125 · 1.375 · 1.75 · 2.25 · 3.
Line height 1.5 for body, 1.2 for headings, 1.65 for Devanagari body. Numbers use tabular figures
in counters.

## 4. Space, shape, depth

- **Spacing:** 4 px base. Tokens `--space-1…8` = 4, 8, 12, 16, 24, 32, 48, 64.
- **Radii:** 6 px for controls, 12 px for sheets and dialogs, round for instruments and pills.
  Plots on the map are square-cornered parcels with a 1 px ink hairline.
- **Depth:** a chart lies flat, so shadows are low: `0 1px 0 var(--line)`, plus
  `0 8px 24px rgb(21 32 42 / 0.08)` for sheets. Dark mode uses a lighter sheet surface instead of
  shadows.
- **Touch:** at least 44 × 44 px targets, 48 px for primary actions on phones. The primary thumb
  zone is the bottom third of the screen.

## 5. Motion

- **Durations:** 120 ms for micro feedback (press, toggle), 200 ms for UI state changes, 320 ms
  for sheets.
- **Easing:** `cubic-bezier(.2,.8,.2,1)` standard; `cubic-bezier(.3,0,.2,1)` for sheets.
- **Camera:**
  - Fly-to uses the van Wijk–Nuij smooth zoom-and-pan path (the same family as web maps): it zooms
    out, travels and zooms in.
  - Duration scales with distance, from 0.8 s to 2.2 s, and is interruptible at any frame.
  - Pan has momentum with friction 0.92 per frame; pinch zoom is anchored under the fingers.
- **The magic moment:** after signup, a 2 s fly from the world view to your neighborhood. Your
  plot's pin drops with one soft bounce, then your neighbors' thumbnails fade in, nearest first.
- **Reduced motion:** fly-to becomes a 150 ms cross-fade, momentum is off and the pin doesn't pulse.
  Nothing essential depends on motion.
- **Frame budget:** animations only use transforms and opacity in the DOM. Everything on the map
  goes through PixiJS.

## 6. Core components

| Component                           | Notes                                                                                                                                                                                    |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Map instruments**                 | Bottom-right cluster (thumb zone): zoom ±, compass (tap to reset north and zoom), "wander" die, locate-my-plot pin. Round, ink-lined, 48 px on phones.                                   |
| **Search pill and command palette** | Top-center pill "Search people, topics, regions" (Cmd/Ctrl+K). The palette lists results grouped by People, Regions and Topics, plus Actions. Enter flies the camera there.              |
| **Breadcrumbs**                     | Top-left, atlas style: `CONTINENT › Region › @handle`. Each part flies to that level.                                                                                                    |
| **Minimap**                         | Inset map with a hairline frame, bottom-left on desktop; tucked behind the compass on phones.                                                                                            |
| **Bottom sheet**                    | Plot details, comments and moderation notices. Three snap points (peek, half, full), drag handle, keyboard-operable, focus-trapped when full. Becomes a side panel at 1024 px and wider. |
| **Plot card**                       | Thumbnail with ThumbHash placeholder, handle, one-line description, region color tick.                                                                                                   |
| **Item badge "In review"**          | Dashed warning outline, clock icon and the label "In review". The owner sees it only on their own items.                                                                                 |
| **Moderation notice**               | Sheet section explaining what was blocked and why, with an "Appeal" button. Copy rules in section 8.                                                                                     |
| **Handle picker**                   | Live availability check, allowed characters shown as you type, a suggestion from your Google or GitHub name.                                                                             |
| **Template gallery**                | Five cards: game project, portfolio, startup idea, research, art. Each is a small pre-arranged Excalidraw scene with placeholder text.                                                   |
| **Paste and drop target**           | The whole plot is the target. On drag-over, a dashed ink border and "Drop to add". On paste, an instant optimistic item.                                                                 |
| **Skeletons**                       | Land-colored blocks with a slow sheen (static under reduced motion). Thumbnails always start as their ThumbHash blur, never a blank box.                                                 |
| **Toasts**                          | Bottom-center above the thumb zone, short, with undo where it makes sense.                                                                                                               |
| **Keyboard overlay**                | "?" opens a sheet listing shortcuts, grouped.                                                                                                                                            |

Icons: **Lucide** (ISC license), imported per icon so only the icons we use ship.

## 7. The first minute (target under 60 s)

1. **Landing (0–3 s):** the living map fills the screen behind a short promise and two buttons:
   "Continue with Google" and "Continue with GitHub".
2. **Handle (about 10 s):** pre-filled suggestion, live availability.
3. **One line (about 15 s):** "What's your plot about?" A 120-character limit with a counter and
   example prompts.
4. **One thing (about 15 s):** paste a link, drop an image, or pick a template. Paste works
   immediately.
5. **Fly-in (about 3 s):** the camera flies from the world to your neighborhood; your pin drops and
   your neighbors appear. A single sheet says "Welcome to the frontier of <Region>" and offers
   "Visit a neighbor".

Until your description is placed, the plot sits in the frontier region's coastal shelf. When
placement lands, you get a notification and a short fly to your new home.

## 8. Voice and copy

- **Tone:** warm, short, specific. A few cartographic words ("plot", "region", "wander") and never
  cute in error states.
- **Moderation messages** state what, why and what next, and never blame:
  - "This image is waiting for review. Only you can see it for now. Usually a few minutes."
  - "We couldn't publish this link card: the page it points to is flagged as a scam. If you think
    that's wrong, you can appeal and a person will look at it."
  - "This comment wasn't published because it reads as harassment. You can edit it and try again,
    or appeal."
- All strings live in `messages/<locale>.json`. No string concatenation for sentences; use ICU
  messages so Hindi word order works.

The UX copy skill (Anthropic "design" plugin) is suggested but not yet enabled. These strings get a
pass with it when it is enabled.

## 9. Speed budgets (hard targets, checked every phase)

Reference: Lighthouse mobile (Moto G Power class emulation, slow 4G, 4× CPU slowdown) and a real
mid-range Android phone when available.

| Metric                                                         | Budget                                                                                |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| World viewer initial JS (gzip)                                 | ≤ 180 KB, including PixiJS core (tree-shaken)                                         |
| Initial map data (`world.json` + regions + first chunks, gzip) | ≤ 100 KB                                                                              |
| Largest Contentful Paint                                       | ≤ 2.5 s                                                                               |
| Time to interactive (pan works)                                | ≤ 3.5 s                                                                               |
| Total Blocking Time                                            | ≤ 200 ms                                                                              |
| Cumulative Layout Shift                                        | ≤ 0.05                                                                                |
| Pan and zoom                                                   | 60 fps target; 95th-percentile frame ≤ 16.7 ms; never below 30 fps                    |
| Editor (Excalidraw)                                            | Lazy chunk, prefetched on edit intent; interactive ≤ 2.5 s after tapping "Edit" on 4G |
| Thumbnail                                                      | ≤ 40 KB WebP at 512 px; ThumbHash about 25 bytes in the layout data                   |
| Save                                                           | Optimistic; queued offline; flushed within 2 s when online                            |

Every phase reports these numbers (Lighthouse CI run locally with the pre-installed Chromium, plus
Playwright frame-time traces for panning).

## 10. Accessibility (WCAG 2.2 AA minimum)

- **Contrast:** text at least 4.5:1 (all text tokens pass in both themes; see 2.1). Interactive
  boundaries at least 3:1.
- **Focus:** a 2 px `--accent` ring with a 2 px offset, always visible on keyboard focus.
- **Map by keyboard:**
  - arrows pan, `+`/`-` zoom, `0` resets
  - Tab moves through plots in view in reading order and Enter opens one
  - `g` then `r` jumps to a region, `/` opens search
- **Screen readers:**
  - The canvas is `aria-hidden`, with a parallel DOM of landmarks, region headings and plot links.
  - A polite live region announces "Entered Indie Games, 214 plots".
- **List view:** any region as a plain, sortable list of plots. It's also the fallback when WebGL is
  unavailable.
- **Alt text:** prompted on every image upload, pre-filled from Claude's description when
  available. The owner confirms it.
- **Reduced motion and transparency** are honored, and high-contrast mode (`forced-colors`) uses
  system colors for coastlines and labels.
- **Input:** touch targets at least 44 px, no hover-only actions, every gesture has a button
  equivalent.

## 11. Internationalization

- `next-intl` with ICU messages. English first, Hindi next.
- Logical CSS properties (`margin-inline`, `inset-inline`) everywhere, so right-to-left scripts work
  later.
- `Intl` for numbers, dates and relative times.
- Fonts already cover Devanagari (section 3).
- Region and continent names from Claude are stored per locale when translations are added (named
  once per locale, then cached).

## 12. Measuring the experience

- **First-minute funnel:** landing → OAuth complete → handle → description → first item → fly-in
  completed, with the time taken at each step.
- **Return visits** within 7 and 30 days; **neighbor exploration** (plots opened per session that
  aren't yours, wander uses).
- **Tooling:** Cloudflare Web Analytics for traffic (free, cookieless). PostHog free tier only if we
  need these funnels, with its billing limit at $0. No third-party ad trackers.
