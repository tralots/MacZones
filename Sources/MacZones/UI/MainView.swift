import SwiftUI

struct MainView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: selection) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .badge(pane == .general && !state.axTrusted ? Text("!") : nil)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch state.pane {
                case .layouts: LayoutsView()
                case .behavior: BehaviorView()
                case .appearance: AppearanceView()
                case .shortcuts: ShortcutsView()
                case .general: GeneralView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(state.pane.title)
        }
    }

    private var selection: Binding<Pane?> {
        Binding(get: { state.pane }, set: { if let pane = $0 { state.pane = pane } })
    }
}
