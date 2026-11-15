import CoreGraphics
import Testing
@testable import MarineSimulator

@Suite
@MainActor
struct ResponsiveLayoutTests {

    @Test
    func widthClassesFollowAvailableContentWidth() {
        #expect(DesignToken.Window.minimumWidth == 960)
        #expect(DesignToken.Window.minimumHeight == 640)
        #expect(ResponsiveLayout.targetMinimumContentWidth == 720)
        #expect(DesignToken.Breakpoint.regular == 720)
        #expect(DesignToken.Breakpoint.wide == 900)
        #expect(DesignToken.Breakpoint.wide == DesignToken.Width.configurationCardMinimum * 2 + DesignToken.Spacing.section)
        #expect(ResponsiveLayout.twoColumnContentWidth == DesignToken.Breakpoint.wide)
        #expect(ResponsiveLayout.widthClass(for: 719) == .compact)
        #expect(ResponsiveLayout.widthClass(for: 720) == .regular)
        #expect(ResponsiveLayout.widthClass(for: 800) == .regular)
        #expect(ResponsiveLayout.widthClass(for: DesignToken.Breakpoint.wide - 1) == .regular)
        #expect(ResponsiveLayout.widthClass(for: DesignToken.Breakpoint.wide) == .wide)
    }

    @Test
    func configurationCardsStayWithinTheReadableWidthTokens() {
        #expect((16...24).contains(ResponsiveLayout.configurationGutter))
        #expect((440...520).contains(ResponsiveLayout.configurationCardMinimum))
        #expect((440...520).contains(ResponsiveLayout.configurationCardMaximum))
        #expect((1100...1200).contains(ResponsiveLayout.adaptivePageMaxWidth))
        #expect(PageChrome.maxWidth == 920)
    }

    @Test
    func boatRowsStackOnlyWhenTheCompactGridDoesNotFit() {
        #expect((140...160).contains(ResponsiveLayout.formLabelWidth))
        #expect((12...16).contains(ResponsiveLayout.formColumnGap))
        #expect((280...360).contains(ResponsiveLayout.formValueMinimum))
        #expect((280...360).contains(ResponsiveLayout.formValueIdeal))
        #expect((280...360).contains(ResponsiveLayout.formValueMaximum))
        let threshold = ResponsiveLayout.formRowCompactWidth
        #expect(ResponsiveLayout.formRowStyle(for: threshold - 1) == .stacked)
        #expect(ResponsiveLayout.formRowStyle(for: threshold) == .compactGrid)
        #expect(ResponsiveLayout.formValueColumnWidth(for: threshold) == ResponsiveLayout.formValueMinimum)
        #expect(ResponsiveLayout.formValueColumnWidth(for: 1200) == ResponsiveLayout.formValueMaximum)

        let constrainedDetail = boatFormRowWidth(detailColumn: 400)
        let regularDetail = boatFormRowWidth(detailColumn: ResponsiveLayout.targetMinimumContentWidth)
        #expect(constrainedDetail < threshold)
        #expect(ResponsiveLayout.formRowStyle(for: constrainedDetail) == .stacked)
        #expect(ResponsiveLayout.formRowStyle(for: regularDetail) == .compactGrid)
        #expect(BoatProfileLayout.libraryWidth == 320)
    }

    @Test
    func toolbarTitlesComeFromTheSidebarAndPagesDoNotRepeatThem() {
        let expected: [(SidebarItem, String)] = [
            (.dashboard, "Dashboard"),
            (.connection, "Connection"),
            (.simulation, "Simulation"),
            (.boat, "Boat Profile"),
            (.diagnostics, "Diagnostics"),
            (.manual, "Manual"),
            (.sentencesOverview, "Overview"),
            (.wind, "Wind"),
            (.compass, "Compass"),
            (.hydro, "Hydro"),
            (.gps, "GPS"),
        ]
        #expect(expected.map(\.0).count == SidebarItem.allCases.count)
        for (item, title) in expected {
            #expect(item.pageTitle == title)
            #expect(PageTitlePresentation.toolbarTitle(for: item) == title)
            #expect(PageTitlePresentation.inContentPageTitle(for: item) == nil)
            #expect(title != "MarineSimulator")
        }
        #expect(SidebarItem.diagnostics.pageTitle != "Experiment Diagnostics")
        #expect(PageTitlePresentation.shellOwnsTopSeparator)
        #expect(ShellChrome.pagesAddTopSeparator == false)
        #expect(ShellChrome.topSeparatorHeight == 1)
    }

    @Test
    func formEditorsUseTheVisibleTitleAsTheirAccessibilityLabel() {
        for title in ["Name", "LOA", "Luff", "Area", "UUID"] {
            #expect(FormRowAccessibility.editorLabel(title) == title)
        }
        #expect(FormRowAccessibility.readOnlyKeepsVisibleTitle)
    }

    @Test
    func responsiveSliceKeepsTheExistingDestinationLifecycles() {
        #expect(SidebarItem.connection.lifecycle == .retainedForm)
        #expect(SidebarItem.simulation.lifecycle == .retainedForm)
        #expect(SidebarItem.boat.lifecycle == .retainedSessionView)
        #expect(SidebarItem.connection.retainsDestinationTree)
        #expect(SidebarItem.simulation.retainsDestinationTree)
        #expect(SidebarItem.boat.retainsDestinationTree)
        #expect(SidebarItem.manual.lifecycle == .ephemeral)
        #expect(SidebarItem.manual.retainsDestinationTree == false)
        #expect(SidebarItem.gps.lifecycle == .retainedMapResource)
        #expect(SidebarItem.gps.retainsDestinationTree)
        #expect(SidebarItem.dashboard.lifecycle == .retainedDashboardMap)
        #expect(SidebarItem.dashboard.placesConsoleInTheShell == false)
        for page in [SidebarItem.diagnostics, .sentencesOverview, .wind, .hydro, .compass] {
            #expect(page.lifecycle == .retainedForm)
            #expect(page.retainsDestinationTree)
        }
    }

    private func boatFormRowWidth(detailColumn: CGFloat) -> CGFloat {
        detailColumn - PageChrome.padding * 2 - BoatProfileLayout.cardPadding * 2
    }
}
