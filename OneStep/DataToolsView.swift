import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct DataToolsView: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var transfer = LocalTransfer()
    @State private var file = BackupFile(data: Data())
    @State private var exporting = false
    @State private var importing = false
    @State private var pending: TransferDocument?
    @State private var code = ""
    @State private var name = ""
    @State private var host = ""
    @State private var receiving = false
    @State private var showPreview = false
    @State private var recovery: [URL] = []
    @State private var releaseMessage = ""

    var body: some View {
        Form {
            Section("Your space") {
                TextField("Profile name", text: $name)
                Button("Save local profile") {
                    var next = store.state; var profile = next.profile ?? LocalProfile()
                    profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !profile.name.isEmpty else { return }
                    next.profile = profile; _ = store.commit(next)
                }
                Text("A local profile works without a login. Pairing copies the profile with your planner; it doesn't prove online account ownership.").font(.footnote)
            }
            Section("Backup and restore") {
                Button("Export backup") {
                    do { file = BackupFile(data: try store.exportData()); exporting = true }
                    catch { store.errorMessage = error.localizedDescription }
                }
                Button("Import backup") { importing = true }
                Text("JSON backups contain readable personal data. Keep them somewhere private. Import previews the data, saves a recovery copy, then replaces this device's planner. Active timers stay on their original device.").font(.footnote)
                ForEach(recovery, id: \.self) { url in ShareLink("Recovery: \(url.lastPathComponent)", item: url) }
            }
            Section("Send over local Wi-Fi") {
                TextField("This device's local IPv4 address", text: $host).keyboardType(.numbersAndPunctuation)
                Button("Create 10-minute transfer code") {
                    do {
                        if store.state.profile == nil { var next = store.state; next.profile = LocalProfile(); guard store.commit(next) else { return } }
                        try transfer.start(data: store.exportData(), host: host)
                    } catch { store.errorMessage = error.localizedDescription }
                }
                if !transfer.invitation.isEmpty {
                    ShareLink("Share pairing code", item: transfer.invitation)
                    Button("Copy pairing code") { UIPasteboard.general.string = transfer.invitation }
                    Text(transfer.invitation).font(.caption.monospaced()).textSelection(.enabled)
                    Button("Stop sharing") { transfer.stop() }
                }
                Text(transfer.message).font(.footnote)
                Text("Use the same private Wi-Fi network. Keep both apps open. No router port forwarding or server is needed. On Windows, allow private-network access if prompted.").font(.footnote)
            }
            Section("Receive from another device") {
                TextField("Paste pairing code", text: $code, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(receiving ? "Receiving…" : "Receive and preview") {
                    receiving = true
                    Task {
                        defer { receiving = false }
                        do { pending = try await LocalTransfer.receive(code); showPreview = true }
                        catch { store.errorMessage = "Transfer failed. Keep the sender open and check the code, Wi-Fi, and local-network permission. \(error.localizedDescription)" }
                    }
                }.disabled(receiving || code.isEmpty)
                Text("This is a manual snapshot transfer, not automatic conflict merging. Export both devices first if they have different edits.").font(.footnote)
            }
            Section("Optional online account") {
                NavigationLink("Bank, rewards, and account") { RewardsView() }
                Text("Beta enrollment and secure account sessions are separate from your local planner profile.").font(.footnote)
            }
            Section("App updates") {
                NavigationLink("Content updates without reinstalling") { ContentUpdatesView() }
                Button("Check GitHub releases") { Task { await checkReleases() } }
                Link("Open build downloads", destination: URL(string: "https://github.com/sillytira/onestep-ios/actions")!)
                Text(releaseMessage).font(.footnote)
                Text("Native code changes still require installing and signing a new IPA. This app cannot renew Apple's free signing profile or replace its own executable. Release checks are optional and contact GitHub only when tapped.").font(.footnote)
            }
        }
        .navigationTitle("Data and devices")
        .task { name = store.state.profile?.name ?? "My space"; host = LocalTransfer.addresses().first ?? ""; loadRecovery() }
        .onDisappear { transfer.stop() }
        .onChange(of: phase) { _, value in if value != .active { transfer.stop() } }
        .fileExporter(isPresented: $exporting, document: file, contentType: .json, defaultFilename: "OneStep-backup") { result in
            if case .failure(let error) = result { store.errorMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 8 * 1024 * 1024 else { throw TransferError.invalid }
                pending = try TransferDocument.decode(Data(contentsOf: url)); showPreview = true
            } catch { store.errorMessage = error.localizedDescription }
        }
        .confirmationDialog("Replace this device's planner?", isPresented: $showPreview, titleVisibility: .visible) {
            Button("Import snapshot", role: .destructive) {
                if let pending, store.importDocument(pending) { name = store.state.profile?.name ?? "My space"; loadRecovery(); store.feedback = "Imported. Your previous planner is in recovery backups." }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            if let pending { Text("\(pending.state.profile?.name ?? "Unnamed space"): \(pending.state.tasks.count) tasks, \(pending.state.routines.count) routine steps, \(pending.state.days.count) history records, \(pending.state.notes?.count ?? 0) notes. This replaces local data after saving a recovery copy.") }
        }
    }

    private func loadRecovery() {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        recovery = (try? FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)) ?? []
    }

    private func checkReleases() async {
        do {
            let (data, response) = try await URLSession.shared.data(from: URL(string: "https://api.github.com/repos/sillytira/onestep-ios/releases/latest")!)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = json["tag_name"] as? String else {
                releaseMessage = "No published release yet. The latest beta builds are under Actions."; return
            }
            releaseMessage = "Latest published release: \(tag). Installed: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")."
        } catch { releaseMessage = "Couldn't check releases. Your offline planner is still available." }
    }
}

struct NotesView: View {
    @Environment(PlannerStore.self) private var store
    @State private var editing: NoteEntry?
    @State private var creating = false
    var body: some View {
        List {
            ForEach((store.state.notes ?? []).sorted { $0.updatedAt > $1.updatedAt }) { note in
                Button { editing = note } label: { VStack(alignment: .leading) { Text(note.title).font(.headline); Text(note.body).lineLimit(2).foregroundStyle(.secondary) } }
                    .swipeActions { Button("Delete", role: .destructive) { var next = store.state; next.notes?.removeAll { $0.id == note.id }; _ = store.commit(next) } }
            }
        }.navigationTitle("Notes")
        .toolbar { Button("Add note", systemImage: "plus") { creating = true } }
        .sheet(isPresented: $creating) { NoteEditor(note: NoteEntry(title: "", body: "")) }
        .sheet(item: $editing) { NoteEditor(note: $0) }
    }
}

private struct NoteEditor: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var note: NoteEntry
    var body: some View {
        NavigationStack {
            Form { TextField("Title", text: $note.title); TextEditor(text: $note.body).frame(minHeight: 220).accessibilityLabel("Note text") }
                .navigationTitle("A thought to keep")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        note.updatedAt = Date(); var next = store.state; var notes = next.notes ?? []
                        if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index] = note } else { notes.append(note) }
                        next.notes = notes; if store.commit(next) { dismiss() }
                    }.disabled(note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }
    }
}
