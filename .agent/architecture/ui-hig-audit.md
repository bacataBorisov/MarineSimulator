# UI HIG audit

Status: **review against Apple’s Human Interface Guidelines fetched on 2026-11-11.** The dashboard review includes two screenshots from the running app. Interaction, larger text, VoiceOver, and live resizing still require manual inspection.

## Sources

- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos), changelog 28 October 2026
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), updated 9 September 2026
- [Split views](https://developer.apple.com/design/human-interface-guidelines/split-views)
- [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls)
- [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)

## What Apple actually says that applies here

macOS is a large, resizable, keyboard-and-pointer environment. People should be able to resize the window and use the menu bar and keyboard shortcuts. Full screen should be available.

Layout guidance that matters for this window:

- Put important content at the top and leading edge. Align items that belong together. Group them with space or a container.
- Respect safe areas so a toolbar or another view does not cover content.
- On macOS, avoid putting critical controls at the bottom of the window, because people park windows below the screen edge.
- Support text-size changes. Rows should grow instead of clipping. Adjacent items may need to stack.
- Do not communicate meaning by color alone. Prefer system colors, which adapt to Increase Contrast and to Light and Dark Mode.

Split views and sidebars:

- A sidebar lists top-level destinations. The selected row stays highlighted. The detail pane shows that destination.
- One or two levels in the sidebar is enough. Labels should be short.
- People should be able to hide the sidebar. macOS already provides that for `NavigationSplitView` when the View menu commands are present. This app does not add its own.
- Sidebar icons follow the user’s accent color unless a fixed color has a specific meaning.
- On macOS, a split view may be resized, and a pane that can hide should have more than one way back.

Accessibility:

- VoiceOver needs names for controls.
- Contrast guidance cited by Apple is WCAG AA: 4.5:1 for text under 18 points, 3:1 for larger or bold text.
- macOS minimum control size in the accessibility page is 20 by 20 points. The default they cite is 28 by 28.

Apple does not require a black sidebar, a switch-style toggle, a 24-point page inset, or a monospaced NMEA font. Those are project choices.

## Where the app already matches

`NavigationSplitView` plus a sectioned `List` is the native sidebar pattern. Selection is persistent. The detail shows one destination. The toolbar uses `.primaryAction` for Start and Stop, and the menu bar has Start, Copy Console, and settings import and export.

The dashboard keeps the map full-bleed and puts docks and the console in a column, which matches the idea that controls should not cover the working surface. Sentence pages group sentences in `GroupBox` and adapt from two columns to one at 720 points.

The dashboard is hidden from hit testing and from accessibility when another page is selected, so the mounted map does not steal clicks or VoiceOver focus.

## Where the app diverges

**Covered content.** Layout guidance says another view must not obstruct content. The shell now places `ConsolePanelView` under the page in a `VStack` for every destination except the dashboard. The dashboard still draws its console over the map, and its docks sit above that console. This was not confirmed by opening the window in the audit that found the overlay.

**Bottom-weighted diagnostics.** The NMEA block is the last section on a long page, and the console covers the bottom of that page. Apple’s macOS note about not putting critical information at the bottom of a window is relevant because the console is already there. Moving NMEA up is optional. Stopping the overlap is not.

**Sidebar material.** The sidebar background is set to black and the system vibrancy is flattened (`OpaqueSidebarColumnBackground`). Accent-colored sidebar symbols and the system material are the HIG default. A black column in Light Mode is a project look, and it should be checked for contrast. It is not an Apple requirement.

**Text size.** Several labels use a fixed point size or `minimumScaleFactor`, including rail headers and `ViewKit.displayLabel`. Fixed field widths in Diagnostics (110 and 140 points) do not stack when text grows. That needs a manual pass with a larger text size. It is not proven broken here.

**Color.** Status often has both a symbol and a color, which meets the “not color alone” rule. The console gradient is custom RGB. Its contrast against `consoleLinePrimary` was not measured.

**VoiceOver.** Some boat and dashboard controls have labels. Diagnostics buttons rely on their titles, which is enough for VoiceOver to speak the title. The NMEA value is a `Text` without an accessibility label that includes the sentence name, so the row’s spoken order depends on `LabeledContent`. That should be checked in Accessibility Inspector.

## Dashboard consistency review

Context: macOS 26, resizable desktop window, keyboard and pointer. The operator needs stable controls for showing panels, choosing a scenario, changing weather ownership, and scanning status without controls moving when telemetry changes.

**Must fix — unstable top strip.** `TopControlBar` uses `ViewThatFits`, while its wide layout gains and loses status badges and the complete Weather section based on live state. `PresetControl` has only a minimum width. Transient status content therefore participates in the fit decision and can move controls or switch the whole strip between wide and narrow layouts. HIG says adaptive layouts should remain familiar and toolbar groups should be deliberate. Fit decisions should depend on available window width, not changing telemetry.

**Should fix — ambiguous affordance.** Panel toggles, scenario actions, the weather-mode action, passive status badges, and the weather detail button use several custom capsule or square treatments in the same row. Some similarly shaped items act, while others only report status. HIG says to differentiate controls from content, prefer standard components, and make each control’s meaning clear.

**Should fix — too many top-level groups.** The strip has Panels, Scenario, Status, and Weather. Apple recommends minimizing toolbar groups and generally aiming for at most three. Keep stable panel controls and scenario/weather ownership as actions; collapse detailed weather and vessel state into one read-only status summary with a popover.

**Should fix — panel controls are a coherent set.** Apple explicitly cites a macOS segmented control for showing and hiding panes. The three panel visibility controls should share one stable multi-selection treatment and selection state. The five Live Controls tabs are an appropriate single-selection segmented control and are already at Apple’s suggested upper limit.

**Should fix — flexible row geometry remains.** The left rail and tab viewport are fixed, but `ControlSliderView` still combines intrinsic labels, a `Stepper` with a `minWidth`/`maxWidth` range, and an unconstrained trailing live value. Pin the repeated columns to one shared grid or exact widths so value changes cannot shift neighboring controls. Disabled state currently stacks custom opacity on system disabled state, reducing legibility more than necessary.

Recommended smallest implementation slice: stabilize the top strip first. Use no more than three semantic groups, keep their positions stable across simulator state, separate actions from read-only status, and preserve a single compact overflow layout. Treat the left-control row grid as a second slice.

## Project recommendations that are not HIG rules

- Move Diagnostics out of Setup in the sidebar.
- Use one toggle style.
- Use one missing-value word.
- Use a shared grid for readout rows.

Those make the app consistent. Apple does not specify them.
