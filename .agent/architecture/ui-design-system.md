# UI design system

Status: **semantic foundation for the migrated setup and form UI.** This is not a branded theme and not a global visual pass. Tokens use system colors and SwiftUI text styles. Pages that are not listed as migrated keep their current local styles.

## Ownership

`DesignToken` in `Utilities/AppConstants.swift` owns the values. Existing layout names read those values. Do not add a second number for the same role.

| API | Owns |
|---|---|
| `DesignToken` | Spacing, type roles, surfaces, separator, `accentPrimary`, status colors, readable widths, form metrics, content breakpoints, window minimum. |
| `PageChrome` | Page inset, readable column, section spacing, sentence split, sentence card width. `previewColumnWidth` (320) stays a sentence-page measurement. |
| `ResponsiveLayout` | Content width class, configuration column size, and the form-row grid. |
| `BoatProfileLayout` | Boat page rhythm. `libraryWidth` stays 320 and is not a shared token. |
| `ShellChrome` | The one-point separator under the toolbar. Its color is `DesignToken.Separator.standard`. |
| `AppColors` | Console RGB palette, and tinted status colors on pages that are not migrated. |
| `UIConstants.spacing` | Legacy 6-point gap for pages that are not migrated. It is a literal, not an alias of `DesignToken.Spacing`. |

Add a token only when a migrated component uses it. Do not alias a token that has no caller. Do not fold a one-off measurement into the scale just to make the numbers match. The 320-point library, the 320-point manual topics column, endpoint field widths, and the dashboard rail stay where they are.

## Spacing, type, and color

Spacing used by the migrated pages: 4 stacked, 6 related, 8 row, 10 inset, 12 header, 14 field, 16 card, 18 profile card, 20 section, 24 page.

Type roles, all SwiftUI text styles:

| Role | Style | Use |
|---|---|---|
| `section` | `.title3` semibold | Settings card title and a boat or sail section heading. |
| `field` | `.body` | Form label and value. |
| `supporting` | `.caption` | Explanation under a control. |
| `help` | `.caption2` | Secondary note. |
| `status` | `.callout` | Connection health and the all-outputs warning. |

Surfaces: `page` is the window background, `card` is the control background, `subtle` is the settings-card wash, `nested` is a card inside a settings card, `selection` is the unemphasized selected-content color. The separator is `separatorColor`. Dark Mode follows the system colors.

Color roles stay distinct:

| Role | Token | Use |
|---|---|---|
| Accent | `accentPrimary` | Interactive accent. It is `Color.accentColor` today. The window applies it once with `.tint`. A branding change replaces this token only. |
| Selection | `Surface.selection` | Selected content background. Not the accent. |
| Active / success | `Status.success` | Active or successful state, including the library Active badge and transmitting. |
| Warning | `Status.warning` | Warning. Not the accent. |
| Error | `Status.error` | Failed or blocking state. The token name is `error`. There is no `DesignToken` `danger` alias. |
| Info | `Status.info` | Informational status. |
| Neutral | `Status.neutral` | Idle or secondary status text. |

Do not paint warning, error, or active state with `accentPrimary`. Do not retint a status role to match a new accent.

`AppColors.warning`, `info`, `danger`, and `success` remain the tinted colors on Dashboard, Manual, and the sentence pages. `AppColors.danger` is that legacy tint, not an alias of `DesignToken.Status.error`. Do not retint those pages in a token migration. Do not spread the console RGB values.

## Width classes

The window minimum is 960×640 (`DesignToken.Window`). The default size is 1180×760. Resizing stops at the minimum. That minimum is the window, not the page body.

`ResponsiveLayout.widthClass(for:)` classifies the width proposed to the page body after the page inset. It does not measure height. There is no fallback content size and no content-height token. Compact is below 720. Regular is 720 up to, but not including, 900. Wide is 900 and above because two 440-point cards and the 20-point gutter need 900. Sidebar, toolbar, and console can make the body narrower or shorter than those targets. Pages scroll. A 960×640 window does not guarantee a 720×600 content area.

Connection and Simulation use `adaptivePageMaxWidth` (1120). Other `PageContainer` pages keep the 920-point column. Diagnostics still overrides that to 880.

## Rows and setup columns

`CompactFormRow` is the shared boat and sail row. At a row width of at least 446 points the label is a trailing 152-point column, then a 14-point gap, then a leading value column of 280–360. A narrower row stacks the label above the value. `FormTextRow` and `FormMenuRow` put one persistent visible label on that row and the same string on the editor. A unit sits beside the value. The row width is the card's width, not the window class.

Connection and Simulation use the available content width. Below 900 points the cards are one `VStack`. At 900 and above they are an `HStack(alignment: .top)` of leading and trailing `VStack`s, with full-width sections before or after that pair. Only the active width branch is built. Onboard Sensors is in both branches. A hidden connection warning is absent, not a zero-size placeholder. Boat detail observes the highlighted vessel in its own view, reads the current buffer in the row that is on screen, and uses the vessel id as the form identity. Keyboard and focus order remain a manual runtime check.

`SettingsCard` is the setup card. It applies `SettingsCardContract`: the title is a heading (`.isHeader`, heading level 2) and the card is an accessibility group labeled by that title, with child controls left accessible (`.contain`, not combined). Help and status text stay inside the group as readable text. The synchronous AppKit accessibility tree does not expose those SwiftUI heading traits. Live VoiceOver was not run. Boat section titles use the same heading role on their own cards.

## Migrated in this slice

Connection, Simulation, the shared settings card, the shell separator, page background, boat form rows, and the sail inventory and active-sail editors.

## Not migrated

Dashboard, including its rails, top strip, and panels. Manual. Diagnostics. Wind, Compass, Hydro, and GPS, including their `GroupBox` sentence cards and help popovers. The console palette. The forced-black sidebar. Endpoint field widths and the sensor toggle grid. The NMEA readout grid described below.

## Readout row

Still a recommendation for Diagnostics and the inspector. It is not a token and it is not built.

- A `Grid` with two columns.
- The label column has one shared width, about 160 points, leading alignment.
- The value column is leading, monospaced digits, and selectable.
- A missing value is the word Unavailable. It is not `0` and it is not `"--"`.
- A long NMEA sentence wraps inside the value column. The label stays on the first line, top aligned.
- Units are in the value, after the number: `12.0 kn`, `90.0°`.

Truth and measurement stay in separate sections. Do not encode that difference only with color. Editable numbers stay in a text field with the unit as a trailing label. Commit on Return and when the field resigns focus. Reject a bad parse in the field.

## Numbers

NMEA sentences keep `NMEANumericFormatting` and the checksum. Displayed quantities should use a POSIX decimal point as well. A shared display helper can replace `String(format:)` call sites later. It should not change the sentence builder.

| Quantity | Digits |
|---|---|
| Angle | 1 |
| Speed | 1, or 2 where the page is comparing a bias |
| Latitude and longitude | 5 |
| Sentence fields | The sentence's own width |

## Console scroll tracking

`tracksConsoleEdge()` belongs inside a shell-page scroll view, list row, or form section. It is not a dashboard-map behavior. The anchor freezes its page and slot when it binds to its clip view. While the console handle is down, the offset is computed from that gesture's starting sample, and a page that started at the document end stays on that end. A page that fits in the viewport does not move. A resize that is not the console drag does not move it. The update is the clip view, on the macOS 26 minimum.

The same anchor restores that clip view for its frozen `SidebarItem` and slot. `MainView` owns the session. A first visit stays at the scroller's initial origin. A return visit applies the stored document offset during layout, after the document and viewport have a real size, and clamps it to that document. The console height is still one shared value. Restoration leaves the drag flag down. Do not add a second `ScrollPosition` binding beside this clip view.

## What not to add

No chart style, no branded palette, and no fixed custom font. No decorative Liquid Glass. Fixed widths that already protect the dashboard rail stay on the dashboard. Native controls stay native. The sidebar's forced black is a local override, not the macOS 26 sidebar material.
