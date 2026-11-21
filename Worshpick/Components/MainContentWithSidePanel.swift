import SwiftUI

/// HSplitView keeps its panes' widths when the setlist inspector opens, which pushes the window content off screen.
/// This layout gives the side panel a share of whatever width is available instead.
struct MainContentWithSidePanel<MainContent: View, SidePanel: View>: View {
    var sidePanelWidthFraction: CGFloat = 0.42
    var sidePanelMinimumWidth: CGFloat = 240
    var mainContentMinimumWidth: CGFloat = 300
    var sidePanelMaximumWidth: CGFloat = 460
    var sidePanelEdge: HorizontalEdge = .trailing
    @ViewBuilder var mainContent: MainContent
    @ViewBuilder var sidePanel: SidePanel

    var body: some View {
        GeometryReader { geometry in
            let preferredSidePanelWidth = min(sidePanelMaximumWidth, geometry.size.width * sidePanelWidthFraction)
            let widthLeftByMainContent = geometry.size.width - mainContentMinimumWidth
            let sidePanelWidth = max(sidePanelMinimumWidth, min(preferredSidePanelWidth, widthLeftByMainContent))
            HStack(spacing: 0) {
                if sidePanelEdge == .leading {
                    sidePanel.frame(width: sidePanelWidth)
                    Divider()
                }
                mainContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                if sidePanelEdge == .trailing {
                    Divider()
                    sidePanel.frame(width: sidePanelWidth)
                }
            }
        }
    }
}
