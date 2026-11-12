# UI design system

Status: **recommendation.** None of these components exist yet except the containers named as current.

Use the system controls and the containers the app already has. Do not add a parallel color and type scale.

## Current containers to keep

| Token or type | Value or role | Use |
|---|---|---|
| `PageChrome.padding` | 24 | Setup and sentence page inset. |
| `PageChrome.maxWidth` | 920 | Readable column. Diagnostics uses 880 today. Pick one. |
| `PageChrome.stackSpacing` | 20 | Space between cards. |
| `PageChrome.splitBreakpoint` | 720 | Sentence page, two columns or one. |
| `PageChrome.sentenceCardMaxWidth` | 520 | Sentence cards. |
| `AppChrome.liveControlRailOuterWidth` | 352 | Dashboard rail only. Do not reuse it on setup pages. |
| `UIConstants.spacing` | 6 | Tight row spacing inside a sentence card. |

`SettingsCard` is the bordered setup card. `GroupBox` is the sentence card and the diagnostics section. A later pass can make Diagnostics use `SettingsCard` or make Connection use `GroupBox`. One of those, not a third card.

## Recommended row

One readout row, used by Diagnostics and available to the inspector later:

- A `Grid` with two columns.
- The label column has one shared width, about 160 points, leading alignment.
- The value column is leading, monospaced digits, and selectable.
- A missing value is the word Unavailable. It is not `0` and it is not `"--"`.
- A long NMEA sentence wraps inside the value column. The label stays on the first line, top aligned.
- Units are in the value, after the number: `12.0 kn`, `90.0°`.

Truth and measurement stay in separate sections. Do not encode that difference only with color. The section title is the distinction. A delta may follow the value in the same column.

Editable numbers stay in a text field with the unit as a trailing label. Commit on Return and when the field resigns focus, so Prepare cannot miss a typed value. Reject a bad parse in the field. Do not write it to `UserDefaults`.

## Type and color

Prefer SwiftUI text styles: `.title3` for a card title, `.body` for values, `.callout` for explanations, `.caption` for secondary notes. The dashboard rail’s 11-point uppercase label is a local instrument style. Do not copy it onto setup pages.

Prefer semantic colors: `.primary`, `.secondary`, `.orange` for a warning that also has an SF Symbol. `AppColors` hard-codes the console gradient. Leave that on the console until contrast is checked in both appearances. Do not spread those RGB values to other pages.

The sidebar is painted black in `MainView` so it matches the dashboard rails. That is a project choice. It does not follow the system sidebar material, and it stays black in Light Mode. A later pass can restore the system material. Do not invent a second black token meanwhile.

## Controls

macOS toggles default to checkboxes. Sentence rows force `.switch`. Choose one style for a settings row and use it on Diagnostics and the sentence pages. Apple does not require the switch on macOS.

Buttons that change a run use the bordered style, in one row: Prepare, Start, Pause, Resume, Reset. Destructive confirmation stays on the boat page, where delete already asks.

SF Symbols already name the sidebar items. Keep that. Do not add bitmap icons.

## Numbers

NMEA sentences keep `NMEANumericFormatting` and the checksum. Displayed quantities should use a POSIX decimal point as well, so a comma locale does not make a readout look like a different number from the sentence. `String(format:)` in `ViewKit.displayLabel` and in `deg` / `kn` does not promise that. A shared display helper can replace those call sites later. It should not change the sentence builder.

Precision for a readout, until a page has a reason to differ:

| Quantity | Digits |
|---|---|
| Angle | 1 |
| Speed | 1, or 2 where the page is comparing a bias |
| Latitude and longitude | 5 |
| Sentence fields | The sentence’s own width |

## Console scroll tracking

`tracksConsoleEdge()` belongs inside a shell-page scroll view, list row, or form section. It is not a dashboard-map behavior. The anchor freezes its page and slot when it binds to its clip view. While the console handle is down, the offset is computed from that gesture’s starting sample, and a page that started at the document end stays on that end. A page that fits in the viewport does not move. A resize that is not the console drag does not move it. The update is the clip view, on the macOS 26 minimum.

The same anchor restores that clip view for its frozen `SidebarItem` and slot. `MainView` owns the session. A first visit stays at the scroller’s initial origin. A return visit applies the stored document offset during layout, after the document and viewport have a real size, and clamps it to that document. The console height is still one shared value. A callback from one region does not write another region’s offset. Restoration leaves the drag flag down. Do not add a second `ScrollPosition` binding beside this clip view.

## What not to add

No chart style, no spacing scale beyond `PageChrome`, and no theme object. No decorative Liquid Glass. Fixed widths that already protect the dashboard rail stay on the dashboard. Native controls stay native. The sidebar’s forced black is a local override, not the macOS 26 sidebar material.
