import SwiftUI
import Observation
import Security
import CommonCrypto

enum RewardsVault {
    static var service: String { (Bundle.main.bundleIdentifier ?? "OneStep") + ".rewards" }
    static func read(_ key: String) -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: key, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }
    static func write(_ key: String, _ data: Data?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        guard let data else { SecItemDelete(query as CFDictionary); return }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var entry = query; entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(entry as CFDictionary, nil)
            if added != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(added)) }
        } else if status != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

@MainActor @Observable final class RewardsStore {
    static let shared = RewardsStore()
    private var sessionRefresh: Task<Void, Error>?
    var project = PublicService.url
    var key = PublicService.key
    var email = ""
    var password = ""
    var betaKey = ""
    var username = ""
    var publicName = ""
    var optIn = false
    var rankingMetric = "tasks"
    var rankings: [[String: Any]] = []
    var snapshotLoaded = false
    var lastSync = ""
    var message = ""
    var busy = false
    var kind: String?
    var balance = 0
    var admin = false
    var ledger: [[String: Any]] = []
    var users: [[String: Any]] = []
    var issueKind = "normal"
    var issueEmail = ""
    var issuedCode = ""
    var target = ""
    var delta = ""
    var reason = ""
    private var session: [String: Any]?
    var signedIn: Bool { session?["access_token"] is String }
    var accountEmail: String { (session?["user"] as? [String: Any])?["email"] as? String ?? "" }
    var userID: String? { (session?["user"] as? [String: Any])?["id"] as? String }
    init() {
        if let data = RewardsVault.read("session") { session = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
        if let data = RewardsVault.read("kind") { kind = String(data: data, encoding: .utf8) }
        if let id = userID, let data = RewardsVault.read("snapshot.\(id)"), let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            balance = saved["balance"] as? Int ?? 0; ledger = saved["ledger"] as? [[String: Any]] ?? []
            username = saved["handle"] as? String ?? ""; publicName = saved["name"] as? String ?? ""
            lastSync = saved["lastSync"] as? String ?? ""; snapshotLoaded = true
        }
    }
    func action(_ work: @MainActor () async throws -> Void) async {
        guard !busy else { return }; busy = true; message = ""; defer { busy = false }
        do { try await work() } catch { message = error.localizedDescription }
    }
    func configure() throws {
        project = project.trimmingCharacters(in: .whitespacesAndNewlines)
        key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: project), url.scheme == "https", let host = url.host, host.hasSuffix(".supabase.co"),
              url.path.isEmpty || url.path == "/", OnlineAccount.isPublicKey(key) else { throw failure("Use a Supabase HTTPS URL and publishable/anon key. Secret keys are forbidden.") }
        project = "https://\(host)"
        try RewardsVault.write("connection", JSONSerialization.data(withJSONObject: ["url": project, "key": key]))
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "OneStep", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    func request(_ path: String, body: [String: Any]? = nil, auth: Bool = true) async throws -> Any {
        if auth {
            guard signedIn else { throw failure("Sign in first.") }
            if (session?["expires_at"] as? Double ?? 0) <= Date().timeIntervalSince1970 + 60 {
                if let sessionRefresh { try await sessionRefresh.value }
                else {
                    guard let refresh = session?["refresh_token"] as? String else { throw failure("Sign in again.") }
                    let task = Task { @MainActor in
                        let updated = try await self.request("/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": refresh], auth: false)
                        guard self.session?["refresh_token"] as? String == refresh else { throw self.failure("Account changed. Please retry.") }
                        try self.accept(updated)
                    }
                    sessionRefresh = task
                    defer { sessionRefresh = nil }
                    try await task.value
                }
            }
        }
        guard let url = URL(string: project + path), url.scheme == "https", url.host?.hasSuffix(".supabase.co") == true else { throw failure("Configure your connection first.") }
        var request = URLRequest(url: url); request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "apikey")
        if auth, let token = session?["access_token"] as? String { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard data.count <= 1024 * 1024 else { throw failure("Service response too large.") }
        let value: Any
        if data.isEmpty { value = NSNull() } else { value = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? NSNull() }
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            let error = value as? [String: Any]
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw failure(error?["msg"] as? String ?? error?["message"] as? String ?? error?["error_description"] as? String ?? "The account service could not respond (\(status)). Try again; your offline planner is still available.")
        }
        return value
    }
    private func accept(_ value: Any) throws {
        guard var result = value as? [String: Any], result["access_token"] is String else { throw failure("Account creation did not return a session. Check beta enrollment and service settings.") }
        if result["expires_at"] == nil { result["expires_at"] = Date().timeIntervalSince1970 + (result["expires_in"] as? Double ?? 3600) }
        try RewardsVault.write("session", JSONSerialization.data(withJSONObject: result))
        let nextID = (result["user"] as? [String: Any])?["id"] as? String
        if nextID != userID {
            kind = nil; admin = false; balance = 0; ledger = []; rankings = []; users = []
            snapshotLoaded = false; lastSync = ""; publicName = ""; username = ""
            try RewardsVault.write("kind", nil)
        }
        session = result
    }
    func authenticate(create: Bool) async throws {
        try configure()
        var body: [String: Any] = ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password]
        if create { body["data"] = ["beta_key": betaKey.trimmingCharacters(in: .whitespacesAndNewlines), "username": username.trimmingCharacters(in: .whitespacesAndNewlines)] }
        try accept(try await request(create ? "/auth/v1/signup" : "/auth/v1/token?grant_type=password", body: body, auth: false))
        password = ""; betaKey = ""; try await reload()
    }
    func rpc(_ name: String, _ args: [String: Any] = [:]) async throws -> Any { try await request("/rest/v1/rpc/" + name, body: args) }
    func reconnect() async throws {
        guard !accountEmail.isEmpty, !password.isEmpty else { throw failure("Enter the password for this account.") }
        email = accountEmail
        try await authenticate(create:false)
    }
    func reload() async throws {
        let roles = try await request("/rest/v1/onestep_account_kinds?select=kind&limit=1") as? [[String: Any]]
        guard let role = roles?.first?["kind"] as? String else { throw failure("Account enrollment is not ready.") }
        kind = role; try RewardsVault.write("kind", Data(role.utf8))
        balance = (try await rpc("onestep_my_balance") as? NSNumber)?.intValue ?? 0
        ledger = try await request("/rest/v1/onestep_points_ledger?select=event_id,delta,reason,created_at&user_id=eq.\(userID ?? "")&order=created_at.desc&limit=100") as? [[String: Any]] ?? []
        admin = try await rpc("onestep_is_admin") as? Bool ?? false
        let profile = try await request("/rest/v1/onestep_profiles?select=display_name,handle,leaderboard_opt_in&limit=1") as? [[String: Any]]
        username = profile?.first?["handle"] as? String ?? ""
        publicName = profile?.first?["display_name"] as? String ?? ""
        optIn = profile?.first?["leaderboard_opt_in"] as? Bool ?? false
        if role != "kids" {
            do { rankings = try await rpc("onestep_rankings", ["metric": rankingMetric]) as? [[String: Any]] ?? [] }
            catch { message = "Your balance is available. Rankings could not refresh: \(error.localizedDescription)" }
        }
        if admin {
            do { users = try await rpc("onestep_admin_users") as? [[String: Any]] ?? [] }
            catch { message = "Your account is available. Admin accounts could not refresh: \(error.localizedDescription)" }
        }
        if role == "kids", let userID {
            let rows = try await request("/rest/v1/onestep_children?select=offline_pin_verifier,active&child_id=eq.\(userID)&limit=1") as? [[String: Any]]
            if let verifier = rows?.first?["offline_pin_verifier"] as? [String: Any], rows?.first?["active"] as? Bool == true {
                try RewardsVault.write("verifier.\(userID)", JSONSerialization.data(withJSONObject: verifier))
            }
        }
        if let id = userID {
            lastSync = Date().formatted(date: .abbreviated, time: .shortened); snapshotLoaded = true
            try RewardsVault.write("snapshot.\(id)", JSONSerialization.data(withJSONObject: ["balance": balance, "ledger": ledger, "handle": username, "name": publicName, "lastSync": lastSync]))
        }
    }
    func authorizeParentCode(_ parentCode: String, accountID: String? = nil) throws {
            guard let id = accountID ?? userID, let data = RewardsVault.read("verifier.\(id)"),
                  let verifier = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw failure("A parent must configure and sync an offline code first.") }
            let now = Date().timeIntervalSince1970
            let lockData = RewardsVault.read("lock.\(id)")
            let lock = lockData.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Double] } ?? [:]
            guard now >= (lock["until"] ?? 0), now >= (lock["last"] ?? 0) - 60 else { throw failure("Parent code is temporarily locked. Check the clock and try later.") }
            let valid = Self.checkPin(parentCode, verifier: verifier)
            let failures = valid ? 0 : (lock["failures"] ?? 0) + 1
            try RewardsVault.write("lock.\(id)", JSONSerialization.data(withJSONObject: ["last": now, "failures": failures, "until": failures >= 5 ? now + 900 : 0]))
            guard valid else { throw failure("Incorrect parent code.") }
    }
    func signOut(parentCode: String? = nil) async throws {
        if kind == "kids" || kind == nil { try authorizeParentCode(parentCode ?? "") }
        _ = try? await request("/auth/v1/logout", body: [:])
        try RewardsVault.write("session", nil); try RewardsVault.write("kind", nil)
        session = nil; kind = nil; admin = false; ledger = []; users = []; balance = 0; username = ""; publicName = ""; rankings = []; snapshotLoaded = false; lastSync = ""
    }
    static func checkPin(_ pin: String, verifier: [String: Any]) -> Bool {
        guard pin.count == 10, pin.allSatisfy(\.isNumber), verifier["algorithm"] as? String == "pbkdf2-sha256", verifier["iterations"] as? Int == 120000,
              let saltText = verifier["salt"] as? String, let salt = Data(base64Encoded: saltText), salt.count == 16,
              let hashText = verifier["hash"] as? String, let hash = Data(base64Encoded: hashText), hash.count == 32 else { return false }
        let password = Array(pin.utf8); var output = [UInt8](repeating: 0, count: 32)
        let status = password.withUnsafeBufferPointer { pass in salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), UnsafeRawPointer(pass.baseAddress!).assumingMemoryBound(to: Int8.self), password.count,
                saltBytes.bindMemory(to: UInt8.self).baseAddress!, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 120000, &output, 32)
        } }
        guard status == kCCSuccess else { return false }
        return zip(output, hash).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

private struct BankRecord: Identifiable {
    let id: String
    let position: Int
    let value: [String:Any]
    static func rows(_ values: [[String:Any]], key: String) -> [BankRecord] {
        values.enumerated().map { BankRecord(id:$0.element[key] as? String ?? "cached-\($0.offset)",position:$0.offset,value:$0.element) }
    }
}

struct RewardsView: View {
    @State private var model = RewardsStore.shared
    @State private var section = 0
    @State private var creating = false
    @State private var parentCode = ""
    var body: some View {
        @Bindable var fields = model
        Group {
            if !model.signedIn { login }
            else {
                VStack(spacing: 0) {
                    Picker("Bank section", selection: $section) {
                        Text("Home").tag(0); Text("Activity").tag(1)
                        if model.kind != "kids" { Text("Rankings").tag(2) }
                        Text("Account").tag(3)
                    }.pickerStyle(.segmented).padding()
                    if !model.message.isEmpty { Text(model.message).font(.callout).foregroundStyle(.orange).padding(.horizontal).textSelection(.enabled) }
                    if model.busy { ProgressView().padding(8) }
                    if section == 0 { overview }
                    else if section == 1 { activity }
                    else if section == 2 { rankings }
                    else { account }
                }
            }
        }.navigationTitle("OneStep Bank")
        .toolbar {
            if model.signedIn { ToolbarItem(placement:.primaryAction) { Button("Refresh account",systemImage:"arrow.clockwise") { Task { await model.action { try await model.reload() } } }.disabled(model.busy) } }
        }
        .task { if model.signedIn { await model.action { try await model.reload() } } }
    }
    private var login: some View {
        @Bindable var fields = model
        return Form {
            Section {
                Image(systemName:"creditcard.fill").font(.largeTitle).foregroundStyle(ItemPalette.violet.color)
                Text("Your effort, in one place.").font(.title2.bold())
                Text("Earn points with OneStep. View rewards and activity across your devices.").foregroundStyle(.secondary)
            }
            Section(creating ? "Create your account" : "Welcome back") {
                TextField("Email",text:$fields.email).textContentType(.username).textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                SecureField("Password",text:$fields.password).textContentType(creating ? .newPassword : .password)
                if creating {
                    SecureField("Admin-issued beta key",text:$fields.betaKey)
                    TextField("Handle (normal/parent accounts)",text:$fields.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Button(creating ? "Create account" : "Sign in") { Task { await model.action { try await model.authenticate(create:creating) } } }.buttonStyle(.borderedProminent).disabled(model.busy || model.email.isEmpty || model.password.isEmpty)
                Button(creating ? "I already have an account" : "Join with a beta key") { creating.toggle() }
                if model.busy { ProgressView("Connecting…") }
                if !model.message.isEmpty { Text(model.message).foregroundStyle(.orange) }
            }
            Section { Text("Virtual points only. No cash purchases or bank account is created.").font(.footnote).foregroundStyle(.secondary) }
        }
    }
    private var overview: some View {
        ScrollView {
            VStack(spacing:24) {
                VStack(spacing:8) {
                    Text("POINTS ACCOUNT").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                    Text(model.snapshotLoaded ? "\(model.balance)" : "—").font(.system(size:64,weight:.bold,design:.rounded)).minimumScaleFactor(0.5).lineLimit(1)
                    Text("Available points").foregroundStyle(.secondary)
                    Text(model.snapshotLoaded ? "Updated \(model.lastSync)" : "Connect to load your balance").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity).padding(.vertical,12)
                LazyVGrid(columns:[GridItem(.adaptive(minimum:96))],spacing:12) {
                    Button { section = 1 } label: { VStack { Image(systemName:"list.bullet.rectangle");Text("Activity") }.frame(maxWidth:.infinity) }
                    NavigationLink { ScreenTimeView() } label: { VStack { Image(systemName:"hourglass");Text("App time") }.frame(maxWidth:.infinity) }
                    Button { section = 3 } label: { VStack { Image(systemName:"person.crop.circle");Text("Account") }.frame(maxWidth:.infinity) }
                }.buttonStyle(.glass).controlSize(.large).font(.subheadline)
                VStack(alignment:.leading,spacing:18) {
                    HStack { Label("OneStep",systemImage:"sparkle").font(.title2.bold()); Spacer(); Image(systemName:"wave.3.right") }
                    Spacer(minLength:22)
                    Text(model.kind == "kids" ? "OneStep Kids" : "@\(model.username)").font(.title3.weight(.semibold))
                    Text("Earned, one step at a time.").font(.subheadline)
                    Text("VIRTUAL POINTS · NO CASH VALUE").font(.caption2).tracking(1.4).foregroundStyle(.white.opacity(0.7))
                }.padding(24).frame(maxWidth:.infinity,alignment:.leading)
                .background(LinearGradient(colors:[Color(red:0.39,green:0.28,blue:0.65),Color(red:0.13,green:0.12,blue:0.23)],startPoint:.topLeading,endPoint:.bottomTrailing),in:.rect(cornerRadius:26))
                HStack { Text("Recent activity").font(.title3.bold()); Spacer(); Button("See all") { section = 1 } }
                if model.ledger.isEmpty { ContentUnavailableView("No activity yet",systemImage:"tray",description:Text("Your earned points and rewards will appear here.")) }
                else { VStack(spacing:16) { ForEach(BankRecord.rows(Array(model.ledger.prefix(4)),key:"event_id")) { row in transaction(row.value) } } }
                if !PersonalRewards.shared.message.isEmpty { Text(PersonalRewards.shared.message).font(.footnote).foregroundStyle(.secondary) }
            }.padding(20).frame(maxWidth:640)
        }.refreshable { await model.action { try await model.reload() } }
    }
    private var activity: some View {
        List {
            if model.ledger.isEmpty { ContentUnavailableView("No activity yet",systemImage:"tray") }
            ForEach(BankRecord.rows(model.ledger,key:"event_id")) { row in transaction(row.value) }
        }.refreshable { await model.action { try await model.reload() } }
    }
    private func transaction(_ row: [String:Any]) -> some View {
        let value = (row["delta"] as? NSNumber)?.intValue ?? 0
        return HStack(spacing:14) {
            Image(systemName:value > 0 ? "arrow.down" : "lock.open").foregroundStyle(value > 0 ? ItemPalette.mint.color : ItemPalette.violet.color).frame(width:42,height:42).background(.quaternary,in:.circle)
            VStack(alignment:.leading,spacing:4) { Text(row["reason"] as? String ?? "Points activity").font(.subheadline.weight(.medium)); Text(String((row["created_at"] as? String ?? "").prefix(10))).font(.caption).foregroundStyle(.secondary) }
            Spacer(); Text("\(value > 0 ? "+" : "")\(value)").font(.headline).foregroundStyle(value > 0 ? ItemPalette.mint.color : .primary)
        }
    }
    private var rankings: some View {
        @Bindable var fields = model
        return List {
            Section {
                Picker("Rank by",selection:$fields.rankingMetric) { Text("Tasks done").tag("tasks");Text("Points earned").tag("points") }.pickerStyle(.segmented)
                    .onChange(of:model.rankingMetric) { _,_ in Task { await model.action { try await model.reload() } } }
                Text("This week · up to 20 counted tasks and 500 earned points per day.").font(.footnote).foregroundStyle(.secondary)
            }
            if model.rankings.isEmpty { ContentUnavailableView("A fresh start",systemImage:"trophy",description:Text("Public rankings are optional. Join from Account.")) }
            ForEach(BankRecord.rows(model.rankings,key:"handle")) { entry in
                let index = entry.position; let row = entry.value
                HStack { Text("#\(index+1)").foregroundStyle(.secondary);Text(row["display_name"] as? String ?? "Member");Spacer();Text("\((row[model.rankingMetric == "tasks" ? "completed_tasks" : "earned_points"] as? NSNumber)?.intValue ?? 0)").fontWeight(.semibold) }
            }
        }
    }
    private var account: some View {
        @Bindable var fields = model
        return Form {
            Section("Your account") {
                Text(model.accountEmail).textSelection(.enabled)
                Text(model.kind == "kids" ? "Private child account" : "@\(model.username)").foregroundStyle(.secondary)
                NavigationLink("Apple Screen Time") { ScreenTimeView() }
                Text("Family invitations and approvals are available in OneStep Parent and Kids.").font(.footnote)
            }
            if model.kind != "kids" {
                Section("Public profile") {
                    TextField("Display name",text:$fields.publicName)
                    TextField("Handle",text:$fields.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Join the leaderboard",isOn:$fields.optIn)
                    Button("Save profile") { Task { await model.action { _ = try await model.rpc("onestep_update_profile",["profile_name":model.publicName,"profile_handle":model.username,"opt_in":model.optIn]);try await model.reload() } } }.disabled(model.busy)
                }
            }
            if model.admin { adminSection }
            Section("This device") {
                SecureField("Account password to reconnect",text:$fields.password).textContentType(.password)
                Button("Reconnect this account") { Task { await model.action { try await model.reconnect() } } }.disabled(model.busy || model.password.isEmpty)
                if model.kind == "kids" || model.kind == nil {
                    SecureField("10-digit parent code",text:$parentCode).keyboardType(.numberPad)
                    Button("Parent-authorized sign-out") { Task { await model.action { try await model.signOut(parentCode:parentCode);parentCode="" } } }.disabled(model.busy)
                } else { Button("Sign out",role:.destructive) { Task { await model.action { try await model.signOut() } } }.disabled(model.busy) }
            }
        }
    }
    @ViewBuilder private var adminSection: some View {
        @Bindable var fields = model
        Section("Application admin") {
            Picker("Beta account type", selection: $fields.issueKind) { Text("Normal").tag("normal"); Text("Parent").tag("parent"); Text("Kids").tag("kids") }
            TextField("Bind beta key to email (optional)", text: $fields.issueEmail).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Generate single-use beta key") { Task { await model.action { model.issuedCode = try await model.rpc("onestep_issue_beta_key", ["account_kind": model.issueKind, "bound_email": model.issueEmail]) as? String ?? "" } } }.disabled(model.busy)
            if !model.issuedCode.isEmpty { Text(model.issuedCode).textSelection(.enabled).font(.caption.monospaced()) }
            Picker("Account for adjustment", selection: $fields.target) {
                Text("Choose an account").tag("")
                ForEach(BankRecord.rows(model.users,key:"id")) { row in Text(row.value["email"] as? String ?? "Account").tag(row.id) }
            }
            TextField("Point adjustment", text: $fields.delta).keyboardType(.numbersAndPunctuation)
            TextField("Audit reason", text: $fields.reason)
            Button("Record audited adjustment") { Task { await model.action {
                guard let delta = Int(model.delta), delta != 0, abs(delta) <= 10000, !model.target.isEmpty else { return }
                _ = try await model.rpc("onestep_admin_adjust_points", ["target": model.target, "amount": delta, "explanation": model.reason, "event": UUID().uuidString])
                try await model.reload(); model.delta = ""; model.reason = ""
            } } }.disabled(model.busy)
            Text("Admin permissions are checked by the service. Database passwords and privileged project keys are never exposed to this client.").font(.footnote)
        }
    }
}
