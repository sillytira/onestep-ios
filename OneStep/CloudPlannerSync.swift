import SwiftUI
import Observation

@MainActor @Observable final class CloudPlannerSync {
    static let shared = CloudPlannerSync()
    var busy = false
    var enabled = false
    var status = "Sync is off. Your planner stays on this device."
    var pending: PlannerMergeResult?
    var generation = UUID()
    private var base: [String:Any]?
    private var snapshot: [String:Any]?
    private var accountID: String?
    private var revision = 0
    private let account = RewardsStore.shared
    private func file(_ user: String) throws -> URL { try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("sync-\(user).encrypted") }
    private func json(_ state: PlannerState) throws -> [String:Any] { PlannerMerge.shared(try JSONSerialization.jsonObject(with:JSONEncoder().encode(state)) as! [String:Any]) }
    private func document(_ state: [String:Any]) throws -> Data { try JSONSerialization.data(withJSONObject:["format":"OneStep","formatVersion":1,"exportedAt":Date().timeIntervalSinceReferenceDate,"state":state],options:.sortedKeys) }
    private func unpack(_ envelope: String,_ password: String) async throws -> [String:Any] {
        let data = try await Task.detached { try BackupCrypto.open(Data(envelope.utf8),password:password) }.value
        _ = try TransferDocument.decode(data)
        return (try JSONSerialization.jsonObject(with:data) as! [String:Any])["state"] as! [String:Any]
    }
    func enable(_ password: String,store: PlannerStore) async throws {
        await account.load()
        guard account.signedIn,let user = account.userID,password.count >= 12,password.utf8.count <= 1024 else { throw BackupCrypto.CryptoFailure.password }
        let row = try await account.rpc("onestep_sync_read",[:]) as! [String:Any]
        if let envelope = row["envelope"] as? String { _ = try await unpack(envelope,password) }
        guard account.userID == user else { throw TransferError.invalid }
        try RewardsVault.write("sync.password.\(user)",Data(password.utf8));try RewardsVault.write("sync.enabled.\(user)",Data("1".utf8))
        base = nil;pending = nil;await tick(store)
    }
    func pause() { if let user = account.userID { try? RewardsVault.write("sync.enabled.\(user)",Data("0".utf8)) };enabled = false;pending = nil;base = nil;status = "Sync paused. Your encrypted cloud copy is retained." }
    func tick(_ store: PlannerStore) async {
        guard !busy else { return };busy = true;defer { busy = false }
        do {
            await account.load();let user = account.userID
            guard !account.needsReconnect else { status = AccountSessionRules.reconnectMessage;return }
            if accountID != user { accountID = user;base = nil;pending = nil;snapshot = nil }
            guard account.signedIn,let user,RewardsVault.read("sync.enabled.\(user)") == Data("1".utf8) else { enabled = false;return }
            enabled = true;guard pending == nil else { return }
            guard let passwordData = RewardsVault.read("sync.password.\(user)"),let password = String(data:passwordData,encoding:.utf8) else { throw BackupCrypto.CryptoFailure.password }
            if base == nil,let data = try? Data(contentsOf:file(user)),let envelope = String(data:data,encoding:.utf8) { base = try await unpack(envelope,password) }
            let local = try json(store.state)
            let row = try await account.rpc("onestep_sync_read",[:]) as! [String:Any]
            guard account.userID == user else { return }
            let version = (row["revision"] as? NSNumber)?.intValue ?? 0
            let remote: [String:Any]
            if let envelope = row["envelope"] as? String { remote = try await unpack(envelope,password) } else { remote = try json(PlannerState()) }
            guard account.userID == user else { return }
            let baseline: [String:Any]
            if let base { baseline = base } else { baseline = try json(PlannerState()) }
            let merge = PlannerMerge.merge(base:baseline,local:local,remote:remote)
            if !merge.conflicts.isEmpty { pending = merge;snapshot = local;revision = version;generation = UUID();status = "Concurrent edits need your choice. Neither version was discarded.";return }
            if PlannerMerge.equal(merge.state,remote),PlannerMerge.equal(merge.state,local) {
                base = merge.state;if let envelope = row["envelope"] as? String { try Data(envelope.utf8).write(to:file(user),options:[.atomic,.completeFileProtection]) };status = "Up to date. Automatic sync runs while OneStep is open.";return
            }
            try await publish(merge.state,local:local,revision:version,password:password,user:user,store:store)
        } catch { status = "Sync paused; your local planner is safe. \(error.localizedDescription)" }
    }
    private func publish(_ merged: [String:Any],local: [String:Any],revision: Int,password: String,user: String,store: PlannerStore) async throws {
        let clear = try document(merged)
        let encrypted = try await Task.detached { try BackupCrypto.seal(clear,password:password) }.value
        guard account.userID == user else { return }
        let result = try await account.rpc("onestep_sync_publish",["expected_revision":revision,"payload":String(data:encrypted,encoding:.utf8)!]) as! [String:Any]
        guard account.userID == user else { return }
        guard result["status"] as? String == "saved" else { status = "Another device updated first. No local edits were replaced; retrying on the next sync.";return }
        let rebased = PlannerMerge.merge(base:local,local:try json(store.state),remote:merged)
        guard rebased.conflicts.isEmpty else { throw SyncFailure.edited }
        var next = try TransferDocument.decode(document(rebased.state)).state;next.focusSession = store.state.focusSession
        guard store.commit(next) else { throw SyncFailure.save }
        base = merged;try encrypted.write(to:file(user),options:[.atomic,.completeFileProtection]);pending = nil;snapshot = nil
        status = "Synced securely. Timers stay on their original device."
    }
    func resolve(_ choices: [Int:Bool],store: PlannerStore) async {
        guard !busy,let pending,let snapshot,let user = accountID,account.userID == user else { return }
        do {
            guard PlannerMerge.equal(try json(store.state),snapshot) else { self.pending = nil;status = "Your local planner changed. Refresh and review the latest versions.";return }
            busy = true;defer { busy = false }
            guard let data = RewardsVault.read("sync.password.\(user)"),let password = String(data:data,encoding:.utf8) else { throw SyncFailure.save }
            try await publish(pending.resolved(choices),local:snapshot,revision:revision,password:password,user:user,store:store)
        } catch { status = "Could not finish resolving. No local data was replaced. \(error.localizedDescription)" }
    }
    enum SyncFailure: LocalizedError { case edited,save;var errorDescription: String? { "New local edits arrived during sync, or saving was unavailable. Refresh to review the latest state." } }
}
private extension Optional where Wrapped == String {
    func mapAsync<T>(_ transform: (String) async throws -> T) async rethrows -> T? { if let value = self { return try await transform(value) };return nil }
}
struct PlannerSyncView: View {
    @Environment(PlannerStore.self) private var store
    @State private var model = CloudPlannerSync.shared
    @State private var password = ""
    @State private var choices: [Int:Bool] = [:]
    var body: some View {
        Form {
            Section("Automatic encrypted sync") {
                Text("Uses your signed-in account and an encrypted cloud copy. Use the same passphrase on each device. Check this device's local planner before enabling. Back up first.")
                SecureField("Sync passphrase (12+ characters)",text:$password)
                Button("Enable encrypted sync") { let value = password;Task { do { try await model.enable(value,store:store);password = "" } catch { store.errorMessage = error.localizedDescription } } }.disabled(model.busy)
                Text(model.status).font(.footnote)
                if model.busy { ProgressView() }
                Button("Sync now") { Task { await model.tick(store) } }.disabled(model.busy)
                Button("Pause sync") { model.pause() }.disabled(model.busy)
            }
            if let pending = model.pending {
                Section("Resolve conflicting edits") {
                    ForEach(Array(pending.conflicts.enumerated()),id:\.offset) { index,c in
                        VStack(alignment:.leading,spacing:8) {
                            Text(c.label).font(.headline)
                            Text("This device: \(describe(c.local))").font(.caption).textSelection(.enabled)
                            Text("Cloud: \(describe(c.remote))").font(.caption).textSelection(.enabled)
                            Picker("Keep version",selection:Binding(get:{choices[index].map { $0 ? 1:0 } ?? -1},set:{choices[index] = $0 == 1})) { Text("Choose").tag(-1);Text("Use this device").tag(0);Text("Use cloud").tag(1) }
                        }
                    }
                    Button("Apply choices") { Task { await model.resolve(choices,store:store) } }.disabled(model.busy || choices.count != pending.conflicts.count)
                }
            }
            Section { Text("Automatic while open and on resume. Mobile systems do not guarantee background sync. Offline changes stay local until reconnected. Requires service migration 007. The passphrase stays in device secure storage, not on the server.").font(.footnote) }
        }.navigationTitle("Private planner sync").task { await model.tick(store) }.onChange(of:model.generation) { _,_ in choices = [:] }
    }
    private func describe(_ value: Any?) -> String { guard let value else { return "Deleted" };guard let data = try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.fragmentsAllowed]),let text = String(data:data,encoding:.utf8) else { return "Unavailable" };return String(text.prefix(1200)) }
}
