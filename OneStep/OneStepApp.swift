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
        .task { if store == nil { load() }; await store?.refresh(); if UserDefaults.standard.object(forKey: "automaticContentUpdates") as? Bool != false { await ContentLibrary().refresh() } }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await store?.refresh() } }
        }
    }

    private func load() {
        do {
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--preview") {
                let preview = try PlannerStore(inMemory: true)
                _ = preview.saveTask(id: nil, title: "Make a little space for your next idea", notes: "Open your notebook. One sentence is enough to begin.", dueAt: nil, reminder: false, colorName: "blue")
                _ = preview.saveTask(id: nil, title: "Take a walk outside", notes: "", dueAt: nil, reminder: false, colorName: "mint")
                _ = preview.saveRoutine(id: nil, title: "A glass of water", time: Date(), colorName: "violet")
                _ = preview.saveRoutine(id: nil, title: "A moment to stretch", time: Date(), colorName: "coral")
                _ = preview.startFocus(PlannerRules.taskAction(preview.state.tasks[0]), until: Date().addingTimeInterval(900))
                store = preview
                startupError = nil
                return
            }
            #endif
            store = try PlannerStore.shared ?? PlannerStore()
            startupError = nil
        }
        catch { startupError = error.localizedDescription }
    }
}
