import SwiftUI
import FamilyControls
import DeviceActivity
import Observation

@MainActor @Observable final class ScreenTimeModel {
    var state = ScreenTimeShared.load()
    var account = RewardsStore.shared
    var message = ""
    var busy = false
    var parentCode = ""
    var picker = false
    var parentAuthorized = false
    var minuteCost = 1
    var dailyMinutes = 1000
    var minutesRemaining = 0
    var chosenMinutes = 15
    var policyLoaded = false
    var unlockAllowed = false
    var supported: Bool { ScreenTimeShared.enabledBuild && ScreenTimeShared.container != nil }
    var child: Bool { state.childManaged || account.kind == "kids" }
    var authorized: Bool { AuthorizationCenter.shared.authorizationStatus == .approved }
    private let center = DeviceActivityCenter()
    static let activity = DeviceActivityName("onestep.unlock")
    func refreshPolicy() async {
        policyLoaded = false
        do {
            try await account.reload()
            guard let status = try await account.rpc("onestep_economy_status") as? [String:Any], status["version"] as? Int == 6 else { throw NSError(domain:"OneStep",code:1,userInfo:[NSLocalizedDescriptionKey:"The 1-point/minute economy service needs migration 006 before redemption is available."]) }
            minuteCost = 1
            dailyMinutes = status["daily_minutes_limit"] as? Int ?? 0
            minutesRemaining = status["minutes_remaining"] as? Int ?? 0
            unlockAllowed = status["redemption_enabled"] as? Bool ?? false
            policyLoaded = true
        } catch { message = "Could not load the economy upgrade: \(error.localizedDescription)" }
    }
    func configureAuthorization() async {
        await run {
            guard supported else { throw ScreenTimeFailure.unavailable }
            await account.load()
            if account.signedIn && account.kind == nil { try await account.reload() }
            try await AuthorizationCenter.shared.requestAuthorization(for: child ? .child : .individual)
            try ScreenTimeShared.update { $0.childManaged = child }
            if child, let id = account.userID { try RewardsVault.write("screen.childAccount", Data(id.utf8)) }
        }
    }
    func authorizeParent() throws {
        let bound = RewardsVault.read("screen.childAccount").flatMap { String(data: $0, encoding: .utf8) }
        try account.authorizeParentCode(parentCode, accountID: bound ?? account.userID)
        parentAuthorized = true; parentCode = ""
    }
    func saveSelection(_ selection: FamilyActivitySelection) throws {
        guard !child || parentAuthorized else { throw NSError(domain: "OneStep", code: 1, userInfo: [NSLocalizedDescriptionKey: "Parent authorization is required to change blocked apps."]) }
        guard authorized, supported else { throw ScreenTimeFailure.unavailable }
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty else { throw ScreenTimeFailure.selection }
        try ScreenTimeShared.update { $0.selection = selection; $0.enabled = true }
        state = ScreenTimeShared.load()
    }
    func stopBlocking() throws {
        guard !child || parentAuthorized else { throw ScreenTimeFailure.unavailable }
        try ScreenTimeShared.update { $0.enabled = false; $0.unlockUntil = nil; $0.leaseID = nil }
        center.stopMonitoring([Self.activity])
        state = ScreenTimeShared.load()
    }
    private func monitor(until: Date) throws {
        let calendar = Calendar.current
        let start = calendar.dateComponents([.year,.month,.day,.hour,.minute,.second,.timeZone], from: Date().addingTimeInterval(-900))
        let end = calendar.dateComponents([.year,.month,.day,.hour,.minute,.second,.timeZone], from: ShieldLeaseRules.monitorEnd(for: until))
        try center.startMonitoring(Self.activity, during: DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false))
    }
    func purchase(minutes: Int, recovering: Bool = false) async {
        await run {
            guard supported, authorized, state.enabled else { throw ScreenTimeFailure.unavailable }
            guard state.unlockUntil == nil || state.unlockUntil! <= Date() else { throw NSError(domain: "OneStep", code: 1, userInfo: [NSLocalizedDescriptionKey: "An unlock is already active on this device."]) }
            guard let user = account.userID else { throw NSError(domain: "OneStep", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sign in to your points account first."]) }
            let key = "screen.pending.\(user)"
            let pending: [String: Any]
            if let data = RewardsVault.read(key), let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] { pending = value }
            else {
                guard !recovering else { throw NSError(domain: "OneStep", code: 1, userInfo: [NSLocalizedDescriptionKey: "No pending purchase to recover."]) }
                guard policyLoaded, unlockAllowed else { throw NSError(domain: "OneStep", code: 1, userInfo: [NSLocalizedDescriptionKey: "Refresh the unlock policy first. Child purchases need parent approval."]) }
                guard (1...1000).contains(minutes), minutes <= minutesRemaining, minutes <= account.balance else { throw NSError(domain:"OneStep",code:1,userInfo:[NSLocalizedDescriptionKey:"Choose a duration within your balance and remaining daily allowance."]) }
                let device = RewardsVault.read("screen.device").flatMap { String(data: $0, encoding: .utf8) } ?? UUID().uuidString
                try RewardsVault.write("screen.device", Data(device.utf8))
                pending = ["event": UUID().uuidString, "device": device, "duration": minutes, "expected_cost": minutes * minuteCost]
                try RewardsVault.write(key, JSONSerialization.data(withJSONObject: pending))
            }
            // Prove the OS monitor accepts a schedule before spending any points.
            try monitor(until: Date().addingTimeInterval(Double(pending["duration"] as? Int ?? minutes) * 60))
            let response: Any
            do { response = try await account.rpc("onestep_redeem_screen_time", pending) }
            catch {
                if error.localizedDescription.contains("Unlock price changed.") { try RewardsVault.write(key, nil); policyLoaded = false }
                throw error
            }
            guard let receipt = response as? [String: Any],
                  let text = receipt["expires_at"] as? String else { throw ScreenTimeFailure.unavailable }
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallback = ISO8601DateFormatter()
            guard let expiry = formatter.date(from: text) ?? fallback.date(from: text), expiry > Date() else { try RewardsVault.write(key, nil); throw ScreenTimeFailure.expired }
            try monitor(until: expiry)
            guard account.userID == user, ScreenTimeShared.load().enabled, authorized else { throw ScreenTimeFailure.unavailable }
            try ScreenTimeShared.update { $0.unlockUntil = expiry; $0.leaseID = UUID(uuidString: pending["event"] as? String ?? "") }
            try RewardsVault.write(key, nil)
            try? await account.reload()
            await refreshPolicy()
            message = "Unlocked until \(expiry.formatted(date: .omitted, time: .shortened)). The system monitor will restore the shield."
        }
    }
    func run(_ action: () async throws -> Void) async {
        guard !busy else { return }; busy = true; message = ""; defer { busy = false; state = ScreenTimeShared.load() }
        do { try await action() } catch { message = error.localizedDescription }
    }
}

struct ScreenTimeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = ScreenTimeModel()
    @State private var selection = FamilyActivitySelection()
    var body: some View {
        @Bindable var fields = model
        Group {
        if !model.supported {
            ContentUnavailableView {
                Label("Screen Time needs a different signing profile", systemImage:"lock.shield")
            } description: {
                Text("This installed copy cannot use Apple's Family Controls or shared container. Install the Screen Time variant with those capabilities enabled in its signing profiles. The planner, timers, and ordinary reminders work independently.")
            } actions: {
                Link("Apple setup requirements",destination:URL(string:"https://developer.apple.com/documentation/familycontrols")!)
            }
        } else { Form {
            Section("Apple Screen Time") {
                Text(model.child ? "Child mode uses Apple's family authorization and parent-managed unlock policy." : "Self-control mode uses Apple's individual authorization. You remain able to revoke it in system settings.")
                if !model.supported { Text("Use the separately packaged Screen Time IPA with Family Controls/App Group provisioning. The ordinary free-signing beta cannot claim this access.").foregroundStyle(.secondary) }
                Button("Authorize with Apple") { Task { await model.configureAuthorization() } }.disabled(model.busy || !model.supported)
                Text(model.authorized ? "Apple authorization approved" : "Apple authorization not approved")
            }
            if model.child {
                Section("Parent access") {
                    SecureField("Offline parent code", text: $fields.parentCode).keyboardType(.numberPad)
                    Button("Authorize settings changes") { do { try model.authorizeParent() } catch { model.message = error.localizedDescription } }
                    Text("The cached parent verifier works during a backend outage after its initial setup. This does not replace Apple's guardian authentication.").font(.footnote)
                }
            }
            Section("Blocked apps and websites") {
                Label(model.authorized ? "Apple access approved" : "First authorize with Apple",systemImage:model.authorized ? "checkmark.shield" : "1.circle")
                Button("Choose what to block") { selection = model.state.selection; model.picker = true }.disabled(!model.supported || !model.authorized || (model.child && !model.parentAuthorized))
                Text("Selected: \(selection.applicationTokens.count) apps · \(selection.categoryTokens.count) categories · \(selection.webDomainTokens.count) websites").font(.footnote).foregroundStyle(.secondary)
                Button("Apply chosen blocking") { do { try model.saveSelection(selection) } catch { model.message = error.localizedDescription } }.disabled(!model.supported || !model.authorized || (model.child && !model.parentAuthorized))
                Label(model.state.enabled ? "Blocking applied" : "Choose apps, then apply blocking",systemImage:model.state.enabled ? "checkmark.circle.fill" : "2.circle").foregroundStyle(model.state.enabled ? .green : .secondary)
                Button("Stop blocking", role: .destructive) { do { try model.stopBlocking() } catch { model.message = error.localizedDescription } }.disabled(!model.supported || (model.child && !model.parentAuthorized))
            }
            Section("Spend earned points") {
                Button("Refresh price and policy") { Task { await model.refreshPolicy() } }.disabled(model.busy)
                if model.policyLoaded { Text("1 point = 1 minute · \(model.minutesRemaining) of \(model.dailyMinutes) minutes left today (UTC). \(model.unlockAllowed ? "Purchases enabled" : "Parent has not enabled purchases")") }
                if !model.account.signedIn { Text("Sign in from Bank to use earned points. App blocking itself does not require a points purchase.").font(.footnote) }
                Stepper("Choose \(model.chosenMinutes) minutes · \(model.chosenMinutes) points", value:$fields.chosenMinutes, in:1...1000)
                Button("Redeem \(model.chosenMinutes) points") { Task { await model.purchase(minutes:model.chosenMinutes) } }.disabled(model.busy || !model.state.enabled || !model.authorized || !model.policyLoaded || !model.unlockAllowed || model.chosenMinutes > model.minutesRemaining || model.chosenMinutes > model.account.balance)
                ForEach([15,30,60], id: \.self) { minutes in Button("Unlock \(minutes) minutes · \(minutes * model.minuteCost) points") { Task { await model.purchase(minutes: minutes) } }.disabled(model.busy || !model.state.enabled || !model.supported || !model.authorized || !model.policyLoaded || !model.unlockAllowed || minutes > model.minutesRemaining || minutes > model.account.balance) }
                Button("Recover pending purchase") { Task { await model.purchase(minutes: 15, recovering: true) } }.disabled(model.busy || !model.supported || !model.authorized || !model.state.enabled)
                Text("1 point buys 1 minute. Earn and redeem up to 1,000 points per UTC day; a parent can set a lower child unlock limit. XP cannot be spent. Purchases require the service. Retrying a pending purchase reuses its receipt and never charges twice.").font(.footnote)
                if let until = model.state.unlockUntil { Text("Last unlock expiry: \(until.formatted())") }
                Text("A lost connection can leave a purchase pending. Retry to recover the same receipt. If it expired before activation, review it with the administrator; no automatic refund or free unlock is invented.").font(.footnote)
            }
            if !model.message.isEmpty { Section { Text(model.message) } }
        }} }.navigationTitle("Screen Time")
        .familyActivityPicker(isPresented: $fields.picker, selection: $selection)
        
        .task { ScreenTimeShared.reconcile(); model.state = ScreenTimeShared.load(); selection = model.state.selection; await model.account.load(); if model.account.signedIn { await model.refreshPolicy() } }
        .onChange(of:scenePhase) { _, phase in
            if phase != .active { model.parentAuthorized = false; model.parentCode = "" }
            else { ScreenTimeShared.reconcile(); model.state = ScreenTimeShared.load() }
        }
    }
}
