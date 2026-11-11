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
    var project = ""
    var key = ""
    var email = ""
    var password = ""
    var betaKey = ""
    var username = ""
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
    var userID: String? { (session?["user"] as? [String: Any])?["id"] as? String }
    init() {
        if let data = RewardsVault.read("connection"), let value = try? JSONSerialization.jsonObject(with: data) as? [String: String] { project = value["url"] ?? ""; key = value["key"] ?? "" }
        if let data = RewardsVault.read("session") { session = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
        if let data = RewardsVault.read("kind") { kind = String(data: data, encoding: .utf8) }
    }
    func action(_ work: @MainActor () async throws -> Void) async {
        guard !busy else { return }; busy = true; message = ""; defer { busy = false }
        do { try await work() } catch { message = error.localizedDescription }
    }
    func configure() throws {
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
                guard let refresh = session?["refresh_token"] as? String else { throw failure("Sign in again.") }
                let updated = try await request("/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": refresh], auth: false)
                try accept(updated)
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
        if data.isEmpty { value = NSNull() } else { value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            let error = value as? [String: Any]
            throw failure(error?["msg"] as? String ?? error?["message"] as? String ?? error?["error_description"] as? String ?? "The service request failed.")
        }
        return value
    }
    private func accept(_ value: Any) throws {
        guard var result = value as? [String: Any], result["access_token"] is String else { throw failure("Account creation did not return a session. Check beta enrollment and service settings.") }
        if result["expires_at"] == nil { result["expires_at"] = Date().timeIntervalSince1970 + (result["expires_in"] as? Double ?? 3600) }
        try RewardsVault.write("session", JSONSerialization.data(withJSONObject: result)); session = result
    }
    func authenticate(create: Bool) async throws {
        try configure()
        var body: [String: Any] = ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password]
        if create { body["data"] = ["beta_key": betaKey, "username": username] }
        try accept(try await request(create ? "/auth/v1/signup" : "/auth/v1/token?grant_type=password", body: body, auth: false))
        password = ""; betaKey = ""; try await reload()
    }
    func rpc(_ name: String, _ args: [String: Any] = [:]) async throws -> Any { try await request("/rest/v1/rpc/" + name, body: args) }
    func reload() async throws {
        let roles = try await request("/rest/v1/onestep_account_kinds?select=kind&limit=1") as? [[String: Any]]
        guard let role = roles?.first?["kind"] as? String else { throw failure("Account enrollment is not ready.") }
        kind = role; try RewardsVault.write("kind", Data(role.utf8))
        balance = (try await rpc("onestep_my_balance") as? NSNumber)?.intValue ?? 0
        ledger = try await request("/rest/v1/onestep_points_ledger?select=delta,reason,created_at&order=created_at.desc&limit=100") as? [[String: Any]] ?? []
        admin = try await rpc("onestep_is_admin") as? Bool ?? false
        if admin { users = try await rpc("onestep_admin_users") as? [[String: Any]] ?? [] }
        if role == "kids", let userID {
            let rows = try await request("/rest/v1/onestep_children?select=offline_pin_verifier,active&child_id=eq.\(userID)&limit=1") as? [[String: Any]]
            if let verifier = rows?.first?["offline_pin_verifier"] as? [String: Any], rows?.first?["active"] as? Bool == true {
                try RewardsVault.write("verifier.\(userID)", JSONSerialization.data(withJSONObject: verifier))
            }
        }
    }
    func signOut(parentCode: String? = nil) async throws {
        if kind == "kids" || kind == nil {
            guard let parentCode, let id = userID, let data = RewardsVault.read("verifier.\(id)"),
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
        _ = try? await request("/auth/v1/logout", body: [:])
        try RewardsVault.write("session", nil); try RewardsVault.write("kind", nil)
        session = nil; kind = nil; admin = false; ledger = []; users = []; balance = 0
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

struct RewardsView: View {
    @State private var model = RewardsStore()
    @State private var parentCode = ""
    @AppStorage("useSeparateBank") private var separateBank = false
    var body: some View {
        @Bindable var fields = model
        Form {
            if model.busy { ProgressView() }
            if !model.message.isEmpty { Text(model.message).font(.footnote).textSelection(.enabled) }
            if !model.signedIn {
                Section("Connect your service") {
                    TextField("Supabase HTTPS URL", text: $fields.project).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Publishable or anon key", text: $fields.key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("No project key is embedded in this app or source. Connection settings and sessions stay in this device's Keychain. Never enter a service-role or secret key.").font(.footnote)
                }
                Section("Account") {
                    TextField("Email", text: $fields.email).textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                    SecureField("Password", text: $fields.password)
                    SecureField("Beta key for a new account", text: $fields.betaKey)
                    TextField("Handle for a new normal/parent account", text: $fields.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Sign in") { Task { await model.action { try await model.authenticate(create: false) } } }.disabled(model.busy)
                    Button("Create beta account") { Task { await model.action { try await model.authenticate(create: true) } } }.disabled(model.busy)
                    Text("An admin-issued enrollment key is required. Only family-assigned tasks go online; your private planner is never uploaded automatically.").font(.footnote)
                }
            } else {
                Section("Your points") {
                    Label("\(model.balance)", systemImage: "creditcard.fill").font(.largeTitle.bold()).foregroundStyle(ItemPalette.violet.color)
                    Text("Virtual points from approved tasks. No real-money purchases.")
                    Text("App-time spending and Apple Screen Time shielding are not active yet.").font(.footnote)
                    Button("Refresh") { Task { await model.action { try await model.reload() } } }.disabled(model.busy)
                }
                Section("Transactions") {
                    ForEach(Array(model.ledger.enumerated()), id: \.offset) { _, entry in
                        HStack { Text(entry["reason"] as? String ?? "Adjustment"); Spacer(); Text("\((entry["delta"] as? NSNumber)?.intValue ?? 0)").monospacedDigit() }
                    }
                    if model.ledger.isEmpty { Text("No points awarded yet.").foregroundStyle(.secondary) }
                }
                Section("Bank companion") {
                    Toggle("Use the separate Bank app", isOn: $separateBank)
                    if separateBank { Text("Open OneStep Bank and sign in with this same service and account. Both views use the same ledger. The built-in view remains available.").font(.footnote) }
                    Text("Family setup and parent codes are available in OneStep Parent and OneStep Kids.").font(.footnote)
                }
                if model.admin { adminSection }
                Section("This device") {
                    if model.kind == "kids" || model.kind == nil {
                        SecureField("10-digit parent code", text: $parentCode).keyboardType(.numberPad)
                        Button("Parent-authorized device sign-out") { Task { await model.action { try await model.signOut(parentCode: parentCode); parentCode = "" } } }.disabled(model.busy)
                        Text("Signing out does not unlink your family. Only your parent can unlink it. Offline authorization needs a previously synced code verifier.").font(.footnote)
                    } else {
                        Button("Sign out") { Task { await model.action { try await model.signOut() } } }.disabled(model.busy)
                    }
                }
            }
        }.navigationTitle("Bank and rewards")
            .task { if model.signedIn { await model.action { try await model.reload() } } }
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
                ForEach(Array(model.users.enumerated()), id: \.offset) { _, user in Text(user["email"] as? String ?? "Account").tag(user["id"] as? String ?? "") }
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
