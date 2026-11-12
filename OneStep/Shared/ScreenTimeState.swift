import Foundation
import FamilyControls
import ManagedSettings
import Darwin

struct ScreenShieldState: Codable {
    var selection = FamilyActivitySelection()
    var enabled = false
    var childManaged = false
    var unlockUntil: Date?
    var leaseID: UUID?
}
enum ScreenTimeShared {
    static let group = "group.meow.tira.onestep"
    static let settings = ManagedSettingsStore(named: .init("onestep.blocking"))
    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }
    static var enabledBuild: Bool { Bundle.main.object(forInfoDictionaryKey: "OneStepScreenTimeEnabled") as? String == "YES" }
    static func load() -> ScreenShieldState {
        guard let url = container?.appendingPathComponent("shield.json"), let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(ScreenShieldState.self, from: data) else { return ScreenShieldState() }
        return state
    }
    static func update(_ change: (inout ScreenShieldState) -> Void) throws {
        guard let root = container else { throw ScreenTimeFailure.unavailable }
        let fd = open(root.appendingPathComponent("shield.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ScreenTimeFailure.unavailable }
        defer { flock(fd, LOCK_UN); close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw ScreenTimeFailure.unavailable }
        var state = load(); change(&state)
        try JSONEncoder().encode(state).write(to: root.appendingPathComponent("shield.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        apply(state)
    }
    static func reconcile() { try? update { _ in } }
    private static func apply(_ state: ScreenShieldState) {
        let blocking = ShieldLeaseRules.shouldShield(enabled: state.enabled, expiry: state.unlockUntil, now: Date())
        settings.shield.applications = blocking && !state.selection.applicationTokens.isEmpty ? state.selection.applicationTokens : nil
        settings.shield.applicationCategories = blocking && !state.selection.categoryTokens.isEmpty ? .specific(state.selection.categoryTokens) : nil
        settings.shield.webDomains = blocking && !state.selection.webDomainTokens.isEmpty ? state.selection.webDomainTokens : nil
        settings.shield.webDomainCategories = blocking && !state.selection.categoryTokens.isEmpty ? .specific(state.selection.categoryTokens) : nil
    }
}
enum ScreenTimeFailure: LocalizedError {
    case unavailable, selection, expired
    var errorDescription: String? {
        switch self {
        case .unavailable: return "This needs the Screen Time build signed with Family Controls and the shared App Group. Your ordinary planner still works."
        case .selection: return "Choose at least one app, category, or website to block first."
        case .expired: return "That purchase has already expired. No second charge was made. Review the receipt in your account."
        }
    }
}
