# Breadcrumbs — Visual Direction

**One line:** a page from a good paper notebook. Each sprint is a row of hand-ruled boxes,
and ticking one should feel like pressing a pen down firmly, quiet and satisfying.

## Principles
1. **Calm over urgent.** Nothing flashes or turns red, and nothing counts down in your face.
   The check-in is a tap on the shoulder, not an alarm.
2. **Honest, not harsh.** A missed box is still drawn, in a soft sand tone with a short dash.
   It records what happened without judging it.
3. **The box is the hero.** Every screen leads with the row of boxes. Numbers and copy support it.
4. **Few elements, finely made.** One accent colour, one serif for voice, rounded sans for numbers.

## Palette (semantic tokens, light / dark)
| Token | Light | Dark | Use |
|---|---|---|---|
| `paper` | `#FBF9F4` | `#1D1C1A` | Window and panel background |
| `card` | `#FFFFFF` | `#262522` | Raised surfaces |
| `ink` | `#2A2925` | `#EEEAE2` | Primary text |
| `inkSoft` | `#7A766D` | `#A29D93` | Secondary text and captions |
| `rule` | `#E4DFD4` | `#3A3833` | Hairlines and empty box borders |
| `tick` | `#3E7A5A` (deep sage) | `#79C298` | Ticked box fill and primary button |
| `tickInk` | `#FBF9F4` | `#13261B` | Checkmark on a ticked box |
| `missed` | `#E6E0D3` (sand) | `#3B3934` | Missed box fill |
| `missedInk` | `#A49D8E` | `#7B766C` | Dash on a missed box |
| `live` | `tick` at 14% | `tick` at 22% | Progress fill inside the current box |

No red anywhere, and no pure black or pure white text.

## Type
- **Voice:** New York (system serif), medium weight, for questions and headings: "Did you work?",
  "Sprint complete."
- **Numbers:** SF Pro Rounded, semibold, with monospaced digits for timers and counts.
- **UI:** SF Pro Text at 11–13 pt for captions and buttons.

## Shape and spacing
- Boxes are squircles (continuous corners) at about 26% radius, with a 1.5 pt border while empty.
  They sit on a faint ruled baseline like a notebook line.
- Panels have a 22 pt radius, a hairline `rule` border and a soft wide shadow (y 12, blur 40, 12%).
- Use an 8 pt grid: 16 pt outer padding in the popover and 24 pt in panels.

## Box states
| State | Look |
|---|---|
| Pending | Empty, with a `rule` border |
| Current (running) | `tick` border; a `live` fill rises from the bottom as time passes |
| Current (paused) | Same as running with the border dashed, and the fill freezes |
| Awaiting check-in | Full `live` fill with a slow, gentle breathing pulse |
| Ticked | `tick` fill. The checkmark draws on (trim 0→1, 0.35 s), then the box springs 1.0→1.12→1.0 |
| Missed | `missed` fill with a short horizontal dash, fading in over 0.25 s. No bounce |

## Motion
- Spring defaults are response 0.35 and damping 0.7. Nothing loops except the check-in breathing
  (2.4 s, low amplitude).
- Panels fade in and drop 8 pt into place. They leave with a fade only.
- On completion the boxes re-reveal from left to right, 60 ms apart.

## Sound
- A soft two-note chime: a fifth, sine with gentle bell partials, about 1.4 s decay, played at
  moderate volume. It is generated and shipped with the app; there is no system alert sound.

## Surfaces
1. **Menu bar label:** a template glyph (a small ruled box) plus text. Idle shows today's ticked
   count ("12"), running shows the remaining time ("4:32"), paused adds a pause glyph, and while
   waiting for a check-in it reads "Check in".
2. **Popover (MenuBarExtra window, 320 pt):** a header (wordmark and today count), the box row,
   then a state block (Start / timer with Pause and Cancel / check-in prompt), a 7-day mini bar
   strip, and a footer with History, Settings and Quit.
3. **Check-in panel:** a floating card at top-centre, 380 pt wide. It shows the box row, the serif
   question, the caption "Box 3 of 6 · 5 min", and two buttons: **Yes** (filled sage pill, ↩ / Y)
   and **No** (quiet outline, N).
4. **Completion:** the same card shape, reading "Sprint complete.", with the row re-revealed,
   "5 of 6" large, "Today · 17 boxes", and the buttons **Start another sprint** and **Done**.
5. **History window:** today's count large, a 7-day stacked bar chart (ticked in sage, missed in
   sand) with day labels, and the week's totals.
