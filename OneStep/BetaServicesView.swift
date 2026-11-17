import SwiftUI

struct XPBetaView: View {
    @Environment(PlannerStore.self) private var store
    @State private var account = RewardsStore.shared
    @State private var total: Int?
    @State private var today: Int?
    @State private var waiting = 0
    @State private var busy = false
    @State private var status = ""
    var body: some View {
        List {
            Section("XP Beta") {
                Text(total.map { "\($0) XP" } ?? "—").font(.largeTitle.bold())
                if let today { ProgressView(value:Double(today),total:1000);Text("\(today) / 1,000 XP today").font(.caption) }
                Text("One small step = 10 XP")
                Text("XP is not spendable points. Earn up to 1,000 XP per UTC day. Beta earnings stay in their own leaderboard cohort. Skipping and snoozing do not award XP.").font(.footnote)
                if waiting > 0 { Text("\(waiting) completions waiting to sync").foregroundStyle(.orange) }
                Text(status).font(.footnote)
                if busy { ProgressView() }
                Button("Refresh") { Task { await refresh() } }.disabled(busy)
            }
            Section {
                NavigationLink("Account and XP privacy") { RewardsView(initialSection:3) }
                if account.kind != "kids" { NavigationLink("Separate XP leaderboard") { RewardsView(initialSection:2,initialMetric:"xp") } }
            }
        }.navigationTitle("XP Beta").task(id:account.userID) { await refresh() }
    }
    private func refresh() async {
        guard !busy else { return };busy = true;defer { busy = false }
        await account.load()
        guard account.signedIn,let user = account.userID else { total = nil;today = nil;waiting = 0;status = "Sign in to start earning account XP. Your offline planner needs no account.";return }
        await PersonalRewards.shared.sync(store.state)
        let receipts = RewardsVault.read("xp.receipts.\(user)").flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Double] } ?? [:]
        waiting = (store.state.xpCompletions ?? []).filter { $0.accountID.lowercased() == user.lowercased() && receipts[$0.eventKey] != -1 }.count
        do {
            let result = try await account.rpc("onestep_economy_status",[:]) as! [String:Any]
            guard account.userID == user else { total = nil;today = nil;return }
            guard result["version"] as? Int == 6 else { throw TransferError.invalid }
            total = (result["xp_total"] as? NSNumber)?.intValue;today = (result["xp_today"] as? NSNumber)?.intValue
            status = "Server-confirmed XP. Pending completions retry while OneStep is open."
        } catch { status = "XP sync needs a connection and service migrations 006/007. Pending completions stay saved; they are not confirmed XP yet." }
    }
}

struct ModerationView: View {
    @State private var model = RewardsStore.shared
    @State private var owner = false
    @State private var busy = false
    @State private var capabilities: [String] = []
    @State private var users: [[String:Any]] = []
    @State private var audit: [[String:Any]] = []
    @State private var target = ""
    @State private var reason = ""
    @State private var email = ""
    @State private var kind = "normal"
    @State private var message = ""
    @State private var invitation = ""
    @State private var grant: Set<String> = []
    @State private var amount = 10
    @State private var days = 7
    @State private var confirmation: String?
    @State private var adjustmentID: UUID?
    @State private var adjustmentFingerprint = ""
    private let known = ["accounts.read","accounts.ban","points.adjust","invites.issue"]
    private func allowed(_ cap: String) -> Bool { owner || capabilities.contains(cap) }
    var body: some View {
        Form {
            Section {
                Text(owner ? "Owner console":"Assigned moderator permissions").font(.title2.bold())
                Text("Permissions are enforced by the service. Moderators cannot grant rights or suspend an owner. Suspensions stop online service access; offline files and Apple authorization are separate.").font(.footnote)
                if busy { ProgressView() };if !message.isEmpty { Text(message).foregroundStyle(.orange) }
                Button("Refresh") { Task { await run { try await load() } } }.disabled(busy)
            }
            if allowed("accounts.read") {
                Section("Accounts") {
                    ForEach(Array(users.enumerated()),id:\.offset) { _,user in
                        Button { target = user["id"] as? String ?? "";grant = Set(user["permissions"] as? [String] ?? []) } label: { VStack(alignment:.leading) { Text(user["name"] as? String ?? "Account");Text("\(user["kind"] as? String ?? "") · \(user["banned"] as? Bool == true ? "Suspended":"Active")").font(.caption) } }
                    }
                }
            }
            if owner || !capabilities.isEmpty {
                Section { TextField("Target account UUID",text:$target).textInputAutocapitalization(.never).autocorrectionDisabled() }
            }
            if owner {
                Section("Moderator permissions") {
                    ForEach(known,id:\.self) { cap in Toggle(L10n.text(cap),isOn:Binding(get:{grant.contains(cap)},set:{if $0 {grant.insert(cap)} else {grant.remove(cap)}})) }
                    Button("Save permissions") { confirmation = "permissions" }.disabled(busy)
                }
            }
            if allowed("accounts.ban") || allowed("points.adjust") { Section { TextField("Reason (required)",text:$reason,axis:.vertical) } }
            if allowed("accounts.ban") {
                Section("Suspend online access") {
                    Picker("Duration",selection:$days) { Text("Remove suspension").tag(0);Text("1 day").tag(1);Text("7 days").tag(7);Text("30 days").tag(30);Text("10 years").tag(3650) }
                    Button("Apply access change") { confirmation = "ban" }.disabled(busy)
                }
            }
            if allowed("points.adjust") {
                Section("Audited points adjustment") {
                    Stepper("\(amount) points",value:$amount,in: -1000...1000)
                    Button("Record adjustment") { confirmation = "points" }.disabled(busy || amount == 0)
                }
            }
            if allowed("invites.issue") {
                Section("Single-use beta invitation") {
                    TextField("Bound email (optional)",text:$email).textInputAutocapitalization(.never)
                    Picker("Account kind",selection:$kind) { Text("Normal").tag("normal");Text("Parent").tag("parent");Text("Kids").tag("kids") }
                    Button("Generate invitation") { Task { await run { invitation = try await model.rpc("onestep_moderator_invite",["account_kind":kind,"bound_email":email]) as! String } } }.disabled(busy)
                    if !invitation.isEmpty { Text(invitation).font(.caption.monospaced()).textSelection(.enabled) }
                }
            }
            if owner {
                Section("Audit trail") { ForEach(Array(audit.enumerated()),id:\.offset) { _,entry in VStack(alignment:.leading) { Text(entry["action"] as? String ?? "").font(.headline);Text("\(entry["created_at"] ?? "")\n\(entry["actor"] ?? "") → \(entry["target"] ?? "")\n\(entry["details"] ?? "")").font(.caption).textSelection(.enabled) } } }
            }
        }.navigationTitle("Service administration").task { await run { try await load() } }
            .confirmationDialog("Confirm service change?",isPresented:Binding(get:{confirmation != nil},set:{if !$0 { confirmation = nil }}),titleVisibility:.visible) {
                Button("Confirm",role:.destructive) { guard let action = confirmation else { return };confirmation = nil;Task { await run { try await apply(action) } } }
                Button("Cancel",role:.cancel) { confirmation = nil }
            } message: { Text("Account: \(target)\nReason: \(reason)") }
    }
    private func run(_ work: () async throws -> Void) async { guard !busy else { return };busy = true;defer { busy = false };do { try await work() } catch { message = error.localizedDescription } }
    private func load() async throws {
        await model.load();let result = try await model.rpc("onestep_moderation_status",[:]) as! [String:Any]
        owner = result["owner"] as? Bool ?? false;capabilities = result["permissions"] as? [String] ?? []
        if allowed("accounts.read") { users = try await model.rpc("onestep_moderation_users",[:]) as! [[String:Any]] }
        if owner { audit = try await model.rpc("onestep_moderation_audit_read",[:]) as! [[String:Any]] }
        if !owner && capabilities.isEmpty { message = "Owner or assigned moderator access required. Service migration 007 must be active." }
    }
    private func apply(_ action: String) async throws {
        guard UUID(uuidString:target) != nil else { throw TransferError.invalid }
        if action == "permissions" { _ = try await model.rpc("onestep_grant_moderator",["target":target,"permissions":Array(grant)]) }
        if action == "ban" { _ = try await model.rpc("onestep_set_ban",["target":target,"days":days,"explanation":reason]) }
        if action == "points" {
            let fingerprint = "\(target)|\(amount)|\(reason)"
            if adjustmentID == nil || adjustmentFingerprint != fingerprint { adjustmentID = UUID();adjustmentFingerprint = fingerprint }
            _ = try await model.rpc("onestep_moderator_adjust",["target":target,"amount":amount,"explanation":reason,"event":adjustmentID!.uuidString]);adjustmentID = nil
        }
        message = "Change saved and audited.";try await load()
    }
}
