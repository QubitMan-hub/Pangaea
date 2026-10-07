# Design: the living atlas

Pangaea should feel like a beautifully made atlas that happens to be alive, not a SaaS dashboard.
The map is the product; interface chrome is a few precise instruments floating over it. Everything
here is free to ship. Live preview of this direction:
[Pangaea Living Atlas](https://claude.ai/artifact/XsHhTMPw1QqvxRnqvxSze2).

## Identity

- **Nautical-chart conventions:** cool pale water, warm land tinted per region, precise ink
  coastlines, a faint graticule that fades as you zoom in. The dark theme is a night chart.
  Deliberately not the cream-paper, serif and terracotta look generic AI design defaults to.
- **Chart lettering:** region names in IBM Plex Sans italic; headlines in Plex Sans Condensed.
  Labels are always ink, never the region color.
- **Instruments, not toolbars:** round, ink-lined zoom, compass and "wander" controls in the
  thumb zone.
- **"You are here":** your plot's ink pin pulses softly. It is the only animated thing on a
  still map.

## Color tokens

Text always uses the ink tokens. Status colors always come with an icon and a word. Every text
token clears WCAG AA (4.5:1) on `--sea` and `--sheet` in both themes.

| Token       | Light     | Dark      | Use                                          |
| ----------- | --------- | --------- | -------------------------------------------- |
| `--sea`     | `#e3eaec` | `#0b1720` | Background and open water                    |
| `--land`    | `#f1ead6` | `#1d2620` | Base that region washes mix into (map phase) |
| `--sheet`   | `#f7f9f9` | `#13232e` | Sheets, dialogs                              |
| `--ink`     | `#15202a` | `#e6edef` | Text and coastlines (13.6:1 / 15.3:1)        |
| `--ink-2`   | `#44515c` | `#b3c0c6` | Secondary text                               |
| `--ink-3`   | `#5b6873` | `#8e9ca3` | Muted text (4.7:1 / 6.4:1)                   |
| `--line`    | `#c3cfd3` | `#24384a` | Hairlines, graticule                         |
| `--accent`  | `#0f5f86` | `#7cc0e8` | Links, focus ring, selection only            |
| `--success` | `#2a6b45` | `#7cc79a` | Published                                    |
| `--warning` | `#855000` | `#e0a54a` | In review                                    |
| `--danger`  | `#ad2a20` | `#f08a80` | Blocked, destructive                         |

Primary buttons are ink-filled (ink background, sea-colored text), like a stamp.

**Region palette.** Each region keeps one hue for life. The land fill is that hue mixed into
`--land` (26% light, 30% dark); plot blocks use the full hue.

| Slot | Hue        | Light     | Dark      |
| ---- | ---------- | --------- | --------- |
| 1    | terracotta | `#c8553d` | `#e06a4f` |
| 2    | lagoon     | `#0a8fb0` | `#22a6c4` |
| 3    | ochre      | `#bf8a14` | `#d9a23a` |
| 4    | plum       | `#9a46a8` | `#b46ac2` |
| 5    | moss       | `#4f9a3a` | `#6bb356` |
| 6    | indigo     | `#5a4fc4` | `#7d74e0` |
| 7    | rose       | `#d0517f` | `#e06a95` |
| 8    | cobalt     | `#2f6fd0` | `#4f8ae6` |

These were validated with the data-visualization palette validator (OKLab, simulated color-vision
deficiency). Adjacent colorblind ΔE is at least 12.4 in both themes, and ink on any land wash is
at least 7.3:1.

There are only 8 hues because no palette stays distinguishable across more pairs for colorblind
readers. A map only needs neighbors to differ, so regions are colored so that only these pairs ever
touch:

```
1:{2,4,6,8}  2:{1,3,5,6,7}  3:{2,4,6,7,8}  4:{1,3,5}  5:{2,4,6,8}  6:{1,2,3,5,7}  7:{2,3,6,8}  8:{1,3,5,7}
```

Labels and coastlines always carry identity too.

## Type, space, motion

- **IBM Plex Sans** (UI, 400/600) and **Plex Sans Condensed** (headlines, 600), self-hosted. Only
  those two faces are preloaded. Plex Sans Devanagari arrives with Hindi.
- **Scale** (rem): 0.75 · 0.875 · 1 · 1.125 · 1.375 · 1.75 · 2.25 · 3. Line height 1.5 for body,
  1.2 for headings.
- **Spacing:** 4 px base. **Radius:** 6 px for controls, 12 px for sheets. Shadows stay low; dark
  mode uses a lighter surface instead.
- **Touch targets:** at least 44 px, and 48 px for primary actions on phones.
- **Durations:** 120 ms for feedback, 200 ms for state changes, 320 ms for sheets. Easing
  `cubic-bezier(.2,.8,.2,1)`.
- **Camera fly-to:** zooms out, travels and zooms in (van Wijk–Nuij). It takes 0.8–2.2 s depending
  on distance and can be interrupted at any frame. Panning has momentum; pinch zooms under the
  fingers.
- **Reduced motion:** fly-to becomes a 150 ms cross-fade, with no momentum and no pulse.

## First minute (V1)

1. **Explore (0–2 s, no account):** the live map with real plots. Tap any plot to open it.
2. **Claim:** a "Claim your plot" button shows "Continue with Google", with GitHub under "More
   options".
3. **About you (about 10 s):** a handle, pre-filled from the account and checked as you type,
   then "What's your plot about?" in one line (120 characters).
4. **Share (about 15 s):** "What do you want to share?" Text, link or image, then Publish. Paste
   works anywhere. New items show instantly with an "In review" badge.
5. **Fly-in (about 3 s):** the camera flies to the new plot. "Welcome to [region]. Here are 3
   nearby plots." Visiting one completes the core loop.
6. **Afterwards only:** templates (game project, portfolio, startup idea, research, art) and
   "Draw", which opens the full editor.

Target: first content published within 30 seconds of signing in. Never show words like
"embeddings", "model" or "clustering".

## Core components

- **Claim button and sign-in sheet:** one primary action; other providers are tucked away.
- **Composer:** one field that understands text, links and images, with paste and drag-drop.
- **"In review" badge:** dashed warning outline, a clock icon and the label. Only the owner sees it.
- **Moderation notice:** says what was blocked and why, plus an Appeal button.
- **Bottom sheet:** peek, half and full snap points; focus-trapped when full. On desktop it becomes
  a side panel.
- **Plot card:** ThumbHash blur, then the thumbnail, then the handle and the one-line description.
  Never a blank box.
- **Map instruments:** zoom, compass, wander and locate-my-plot, bottom right.

Icons: Lucide, imported one icon at a time.

## Copy

- Warm, short and specific. Moderation messages state what happened, why and what next, and never
  blame:
  - "This image is waiting for review. Only you can see it for now."
  - "This comment wasn't published because it reads as harassment. You can edit it or appeal."
- All strings live in `messages/<locale>.json`, as ICU messages so word order works in Hindi.

## Speed budgets (checked every phase)

Measured with Lighthouse mobile (slow 4G, 4× CPU slowdown).

| Metric                                | Budget                             |
| ------------------------------------- | ---------------------------------- |
| Largest Contentful Paint              | ≤ 2.5 s                            |
| Total Blocking Time                   | ≤ 200 ms                           |
| Cumulative Layout Shift               | ≤ 0.05                             |
| Time to interactive                   | ≤ 3.5 s                            |
| Map viewer JS / first map data (gzip) | ≤ 180 KB / ≤ 100 KB                |
| Pan and zoom                          | 60 fps (95th percentile ≤ 16.7 ms) |
| Thumbnail                             | ≤ 40 KB WebP, 512 px               |

## Accessibility (WCAG 2.2 AA)

- A visible 2 px accent focus ring.
- Full keyboard use: arrows pan, `+`/`-` zoom, Tab moves through plots in view, `/` opens search.
- The map canvas is mirrored by an accessible list of plots; a region list view is also the
  fallback when WebGL is unavailable.
- Image uploads prompt for alt text, pre-filled from the stored description.
- Reduced motion and forced colors are honored, and every gesture has a button equivalent.
