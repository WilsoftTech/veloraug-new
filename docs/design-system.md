# VeloraUG design system

**Version 1. Visual approval: PENDING USER REVIEW.** The owner hasn't approved how this looks yet, so any value here may still change. See the [Step 3B report](step-03b-report.md).

This is the shared specification for the Flutter app and the sign-in pages.

| Where | What |
| --- | --- |
| [`apps/client/lib/theme/tokens.dart`](../apps/client/lib/theme/tokens.dart) | The values, for Flutter |
| [`apps/client/lib/theme/velora_theme.dart`](../apps/client/lib/theme/velora_theme.dart) | `ThemeData` and component themes, built from the tokens |
| [`apps/client/lib/theme/palette.dart`](../apps/client/lib/theme/palette.dart) | `ThemeExtension` for colours `ColorScheme` has no place for |
| [`apps/client/lib/widgets/`](../apps/client/lib/widgets/) | The shared components |
| [`apps/auth_pages/src/tokens.css`](../apps/auth_pages/src/tokens.css) | The same values as CSS custom properties |

`apps/client/test/theme_tokens_test.dart` fails if `tokens.dart` and `tokens.css` disagree on a colour, size or duration. **To change a token, change it in both files and in this document.** Don't write raw colours or sizes anywhere else.

## Direction

A premium, cinematic streaming experience: deep charcoal, one electric blue accent, off-white text, strong type and generous space. Posters will supply most of the colour, so the interface stays quiet. There is no glow, no decorative texture, no autoplay and no flashing.

## Colour

The app has one dark theme.

### Surfaces

| Token | Value | Use |
| --- | --- | --- |
| `canvas` | `#0E1014` | Page background |
| `surface` | `#171A1F` | Cards, panels, navigation bar, field fill |
| `surfaceRaised` | `#1F2329` | Dialogs, hover on quiet controls |
| `surfaceOverlay` | `#2A2F37` | Notifications, tooltips, pressed quiet controls, disabled button fill |

### Text

Minimum contrast is checked on all four surfaces. The target is 4.5:1 (WCAG AA).

| Token | Value | `canvas` | `surface` | `surfaceRaised` | `surfaceOverlay` | Use |
| --- | --- | --- | --- | --- | --- | --- |
| `textPrimary` | `#F4F2EC` | 17.0 | 15.6 | 14.1 | 12.0 | Headings, body text |
| `textSecondary` | `#BCC1CA` | 10.5 | 9.7 | 8.7 | 7.4 | Supporting text, labels |
| `textMuted` | `#9AA1AD` | 7.3 | 6.7 | 6.1 | 5.2 | Hints, placeholder artwork |
| `accentText` | `#7DB2FF` | 8.8 | 8.0 | 7.3 | 6.2 | Links, quiet buttons, selected icons |
| `success` | `#5FD39A` | 10.2 | 9.4 | 8.5 | 7.2 | Success status |
| `warning` | `#F5BE5B` | 11.2 | 10.3 | 9.3 | 7.9 | Warning status |
| `danger` | `#FF8A80` | 8.3 | 7.6 | 6.9 | 5.9 | Errors |

`textDisabled` (`#7F8691`) is for disabled controls only. WCAG exempts those, but it still reaches 3.67:1 on the lightest surface.

### Accent

`accent` is a fill. It is too dark to read as text on charcoal, so use `accentText` for blue text and icons.

| Pair | Contrast | Target |
| --- | --- | --- |
| `onAccent` `#FFFFFF` on `accent` `#1A66F5` | 4.93 | 4.5 |
| `onAccent` on `accentHover` `#1E69F5` | 4.78 | 4.5 |
| `onAccent` on `accentPressed` `#1557D6` | 6.24 | 4.5 |
| `accent` against `canvas`, `surface`, `surfaceRaised` | 3.87, 3.54, 3.20 | 3.0 |

**Don't put a filled button on `surfaceOverlay`:** it only reaches 2.73:1 there.

### Lines and focus

| Token | Value | Use | Contrast |
| --- | --- | --- | --- |
| `outline` | `#7C8491` | The edge of a control | 5.05 on `canvas`, 4.62 on `surface`, 3.57 on `surfaceOverlay` |
| `outlineSubtle` | `#343A43` | Decorative dividers and card edges. Never the only sign of a control | Decorative |
| `focusRing` | `#B8D4FF` | Keyboard focus | 12.6 on `canvas`, 8.91 on `surfaceOverlay`, 3.26 on `accent` |

### Status

Each status has a text colour and a container. **A status always has an icon and words too, never colour alone.**

| Text on container | Contrast |
| --- | --- |
| `success` on `successContainer` `#12291F` | 8.27 |
| `warning` on `warningContainer` `#2C2312` | 9.14 |
| `danger` on `dangerContainer` `#301A1A` | 7.14 |
| `accentText` on `infoContainer` `#14233D` | 7.24 |
| `textPrimary` on `infoContainer` | 14.02 |

## Typography

**No font file is bundled, and no dependency was added.** This first version uses the system stack:

```text
Roboto, Segoe UI, Helvetica Neue, Noto Sans, Arial, sans-serif
```

The sign-in pages can't load web fonts, because their Content-Security-Policy allows only their own site. Flutter on the web fetches its own fallback fonts at runtime, as it did before this step. A distinctive display font could be added later by setting `VeloraFonts.displayFamily`, if the owner wants one: see the [report](step-03b-report.md#questions-for-your-review).

| Style | Size / line height | Weight | Letter spacing | Use |
| --- | --- | --- | --- | --- |
| `displayMedium` | 48 / 52 | 800 | -1 | Home hero, 600 pixels and wider |
| `displaySmall` | 36 / 42 | 800 | -0.5 | Home hero, narrower than 600 pixels |
| `headlineLarge` | 32 / 38 | 700 | -0.5 | Screen headings |
| `headlineMedium` | 28 / 34 | 700 | -0.25 | Large section headings |
| `headlineSmall` | 22 / 28 | 700 | 0 | Section headings, dialog titles |
| `titleLarge` | 20 / 26 | 600 | 0 | State titles, app bar |
| `titleMedium` | 16 / 22 | 600 | 0 | Card headings |
| `titleSmall` | 14 / 20 | 600 | 0 | Movie titles |
| `bodyLarge` | 16 / 24 | 400 | 0 | Running text |
| `bodyMedium` | 14 / 20 | 400 | 0 | Supporting text |
| `bodySmall` | 12 / 16 | 400 | 0 | Helper and error text |
| `labelLarge` | 14 / 20 | 600 | 0.1 | Buttons |
| `labelMedium` | 12 / 16 | 600 | 0.2 | Badges, navigation labels |

12 is the smallest size. Text follows the person's text-size setting and is never capped by these components.

## Spacing, radii, borders and depth

| Spacing token | `xxs` | `xs` | `sm` | `md` | `lg` | `xl` | `xxl` | `xxxl` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Pixels | 4 | 8 | 12 | 16 | 24 | 32 | 48 | 64 |

| Radius | Pixels | Use |
| --- | --- | --- |
| `sm` | 8 | Badges, tooltips, loading placeholders |
| `md` | 12 | Buttons, fields, movie cards, notifications |
| `lg` | 16 | Panels, dialogs, the sign-in card |

| Border | Pixels | Use |
| --- | --- | --- |
| `hairline` | 1 | Control and card edges |
| `focus` | 2 | Focus rings, focused fields |

**Depth comes mainly from lighter surfaces.** A hovered movie card adds a plain black shadow (`0 6px 16px`, 32% black), and dialogs use Material elevation 8. Nothing has a coloured glow.

## Posters, cards and content widths

| Item | Value |
| --- | --- |
| Poster shape | 2:3, width to height |
| Smallest card, narrower than 600 pixels | 136 pixels, with at least two columns |
| Smallest card, 600 pixels and wider | 176 pixels |
| Forms | 420 pixels at most |
| Reading screens, such as Search and Account | 720 pixels at most |
| Browsing screens, such as Home | 1280 pixels at most |

A movie card's height follows its content, and all cards in a row share the tallest height. Titles stop at two lines with an ellipsis, and the full title is always read by screen readers. `MovieCardGrid` builds every card, so a real catalogue will need a lazy grid.

Cards use neutral local artwork until a real poster exists. The real screens show no sample movies, only honest empty states. Demonstration titles appear in the showcase only.

## Responsive behaviour

| Name | Width | Navigation | Side gutter | Home heading |
| --- | --- | --- | --- | --- |
| Compact | Under 600 | Bottom bar | 16 | 36 |
| Medium | 600 to 1023 | Side rail | 32 | 48 |
| Expanded | 1024 and up | Side rail | 48 | 48 |

Top and bottom padding don't change with width, so content starts at the same height on every layout. Every screen scrolls, so large text makes a page longer and doesn't clip it.

The sign-in pages are one centred card, at most 420 pixels wide, with more padding from 600 pixels up.

## States

| State | Filled button | Outlined or quiet button | Field | Movie card |
| --- | --- | --- | --- | --- |
| Default | `accent` | `outline` edge, or none for quiet | `outline` edge, `surface` fill | `outlineSubtle` edge |
| Hover | `accentHover` | `surfaceRaised` fill | Light overlay | `outline` edge and shadow |
| Focus (keyboard) | 2 pixel `focusRing` | 2 pixel `focusRing` | 2 pixel `accentText` edge | 2 pixel `focusRing` |
| Pressed | `accentPressed` | `surfaceOverlay` fill | Not applicable | Scales to 98% |
| Disabled | `surfaceOverlay` fill, `textDisabled` text | `outlineSubtle` edge, `textDisabled` text | `canvas` fill, `outlineSubtle` edge, `textDisabled` label | No action, not offered as a button |
| Loading | Disabled, spinner and a changed label | Same | Not applicable | Use `MovieCardSkeleton` |
| Error | Not applicable | Danger variant for destructive actions | `danger` edge, icon and message | Status badge |
| Success | Not applicable | Not applicable | Not applicable | Status badge |

Navigation items use Flutter's built-in widgets, which draw focus as a fill instead of a ring. `focusColor` is therefore a 32% `focusRing` fill, far stronger than the Material default. It is visible, but it doesn't reach the 3:1 a ring does.

Use Flutter's themed `AlertDialog` and `SnackBar` directly. They don't need wrappers.

## Motion

| Token | Duration | Use |
| --- | --- | --- |
| `fast` | 120 ms | Button and card state changes |
| `standard` | 200 ms | Reserved for small transitions |
| `slow` | 320 ms | Navigation indicator |
| `pulse` | 1400 ms | One full fade of a loading placeholder, between 55% and 100% |

The curve is `easeOutCubic`. No media autoplays, and nothing flashes. The placeholder fade stays well under the WCAG limit of three flashes a second.

**Reduced motion** comes from the system setting, through `MediaQuery.disableAnimations` in Flutter and `prefers-reduced-motion` in CSS.

- Component durations become zero, through `VeloraMotion.of`.
- Loading placeholders hold still.
- The spinner becomes a still hourglass.
- On the sign-in pages, transitions and the pressed scale are removed.

Theme-level button state changes keep their 120 ms colour fade with reduced motion, because a theme can't read the setting. That is a change of colour with no movement.

## Accessibility rules

- WCAG AA contrast for all text, and 3:1 for control edges and focus.
- Every interactive target is at least 48 by 48 logical pixels in Flutter, and at least 48 pixels tall for buttons and fields on the sign-in pages.
- Every control has a visible or spoken label, and icon buttons have tooltips.
- Status always has an icon and words as well as colour.
- Decorative icons are hidden from screen readers.
- Text scaling is never capped, and layouts grow with it.
- Technical diagnostics appear only in debug builds, under a clear "Development tools" heading.
