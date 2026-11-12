import SwiftUI
import Observation

@MainActor @Observable final class ContentLibrary {
    static let feed = URL(string: "https://raw.githubusercontent.com/sillytira/onestep-ios/main/content/catalog.json")!
    var catalog: ContentCatalog?
    var message = ""
    var busy = false
    private var cache: URL? { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("OneStep-content.json") }
    init() {
        if let cache, let data = try? Data(contentsOf: cache) { catalog = try? ContentCatalog.decode(data) }
    }
    func refresh() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            var request = URLRequest(url: Self.feed); request.timeoutInterval = 15; request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.url == Self.feed else { throw ContentError.invalid }
            let value = try ContentCatalog.decode(data)
            guard value.revision >= (catalog?.revision ?? 0) else { throw ContentError.invalid }
            if let cache { try data.write(to: cache, options: [.atomic, .completeFileProtection]) }
            catalog = value; message = "Content is up to date · revision \(value.revision). No IPA installation needed."
        } catch { message = catalog == nil ? "Content couldn't be downloaded. Your planner still works offline." : "Offline or unavailable. Keeping your last checked content." }
    }
}

struct ContentUpdatesView: View {
    @Environment(PlannerStore.self) private var store
    @State private var library = ContentLibrary()
    @State private var pending: ContentPack?
    @AppStorage("automaticContentUpdates") private var automatic = true
    var body: some View {
        Form {
            Section("Updates without a new IPA") {
                Text("Routine packs and their colors refresh inside the installed app. Your tasks, history, and edited routines are never replaced automatically.")
                Toggle("Automatically refresh content", isOn: $automatic)
                Text("Checks the public OneStep content feed when this screen opens. No personal planner data or account tokens are sent.").font(.footnote)
                Button(library.busy ? "Checking…" : "Check content now") { Task { await library.refresh() } }.disabled(library.busy)
                if !library.message.isEmpty { Text(library.message).font(.footnote) }
                Text("New native features still need a signed IPA update. This does not extend Apple's signing expiry.").font(.footnote)
            }
            if let catalog = library.catalog {
                Section("Content revision \(catalog.revision)") { Text(catalog.message) }
                ForEach(catalog.packs) { pack in
                    Section(pack.title) {
                        Text(pack.description)
                        ForEach(Array(pack.steps.enumerated()), id: \.offset) { _, step in
                            Text(String(format: "%02d:%02d · %@", step.hour, step.minute, step.title))
                        }
                        Button(store.state.contentPacks?.contains(pack.id) == true ? "Already added" : "Add these routine steps") { pending = pack }
                            .disabled(store.state.contentPacks?.contains(pack.id) == true)
                    }
                }
            }
            Section("Data privacy") {
                Text("Private planner data stays on this device. iOS protects app files with the device's storage protection. Account sessions use Keychain. Exported JSON backups are readable; store them somewhere private. Content updates contain public templates, never your private tasks.")
            }
        }.navigationTitle("Content updates")
        .task { if automatic { await library.refresh() } }
        .confirmationDialog("Add this routine pack?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Add steps") {
                if let pending, let catalog = library.catalog { _ = store.commit(catalog.installing(pending, in: store.state)) }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { Text("Adds new steps without removing existing routines or changing history. Edit their times in Routines.") }
    }
}
