import SwiftUI

@main
struct OneStepApp: App {
    var body: some Scene {
        WindowGroup { BootstrapView() }
    }
}

struct BootstrapView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: PlannerStore?
    @State private var startupError: String?

    var body: some View {
        Group {
            if let store {
                RootView().environment(store)
            } else if let startupError {
                ContentUnavailableView {
                    Label("Your data needs attention", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("OneStep couldn't open its saved data. It has not been reset.\n\n\(startupError)")
                } actions: {
                    Button("Try again") { load() }.buttonStyle(.borderedProminent)
                }
            } else { ProgressView("Opening OneStep…") }
        }
        .task { if store == nil { load() }; await store?.refresh() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await store?.refresh() } }
        }
    }

    private func load() {
        do { store = try PlannerStore(); startupError = nil }
        catch { startupError = error.localizedDescription }
    }
}
