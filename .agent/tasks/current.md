# Current task

**Status:** Crash fix accepted by the user on 2026-11-12 after varied stress testing.
**Last updated:** 2026-11-11

## Contract

- Remove the full-size hidden Dashboard and its `MKMapView` from non-dashboard page layout.
- Preserve Dashboard state across navigation without adding a second map or console.
- Keep the Dashboard full-bleed and keep exactly one console in the active interface.
- Do not retain every setup page or change operator/experiment runtime ownership.
- Keep navigation transitions unanimated.

## Acceptance

- Non-dashboard navigation no longer lays out a full-size Dashboard or Dashboard map.
- Returning to Dashboard preserves its local controls and map host.
- Dashboard and detail pages still show one console in the correct ownership boundary.
- Existing scroll, navigation, simulator, and diagnostics tests remain green.
- Focused layout, scroll, and diagnostics tests passed; the Debug build succeeded.
- Animation Hitches recorded 124.78–273.01 ms main-thread unresponsiveness and 133.33–366.67 ms render hitches while destinations changed.
- The trace implicates fresh SwiftUI destination construction across multiple pages, not system memory pressure alone.
- At 22:28:22, AppKit raised `NSGenericException`: the window exceeded its Update Constraints passes while the user repeatedly opened and closed the console on Manual.
- Crash-window samples contain `ConsolePanelView.toolbar` and `ConsoleEdgeAnchorView.apply`; they do not contain Dashboard or MapKit frames.
- A zero-size `CAMetalLayer` warning occurred earlier and remains a separate risk, but it is not proven to have caused this crash.
- The console's own show/hide button now cancels drag state and publishes one immediate, animation-disabled height. The AppKit handle arms only after pointer movement.
- `ManualView` no longer uses the crashing SwiftUI `HSplitView`; it uses a fixed 320-point topics column, divider, and flexible article.
- Hosted burst tests, focused layout/scroll suites, and the Debug build passed.
- A 30-second real-app Animation Hitches run with rapid toggling completed without `NSGenericException`; the app remained running. Potential interaction delays were 33.67–53.95 ms and the largest render hitch was 83.33 ms.
- Independent verifier verdict: **Met**, with no blocking findings.
- The user completed several varied stress tests without another crash and accepted the correction.
- The zero-size `CAMetalLayer` warning still occurs and belongs to the unaccepted navigation P0. One post-trace layout-recursion warning remains a separate risk.
- Do not retain every page or choose another Dashboard ownership model without user approval.

## Agreed sequence after the crash fix

1. Finish warmed sidebar-latency measurement and the navigation-performance task.
2. Stabilize the Dashboard top strip against HIG and consistency findings.
3. Stabilize the left Dashboard control-row geometry.
4. Return to the remaining UI plan; do not start M4 automatically.
