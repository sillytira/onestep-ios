import AppIntents
import Foundation

struct DayActionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Update current OneStep action"
    static var isDiscoverable: Bool = false
    @Parameter(title: "Action") var actionID: String
    @Parameter(title: "Snooze") var snooze: Bool
    init() {}
    init(_ actionID: String, snooze: Bool = false) { self.actionID = actionID; self.snooze = snooze }
    @MainActor func perform() async throws -> some IntentResult {
        #if ONESTEP_APP
        let store = try PlannerStore.shared ?? PlannerStore()
        let fields = actionID.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 3, let kind = ActionItem.Kind(rawValue: fields[0]), let id = UUID(uuidString: fields[1]) else { return .result() }
        let reference = ActionItem(kind: kind, sourceID: id, title: "", notes: "", day: fields[2].isEmpty ? nil : fields[2])
        guard let item = PlannerRules.currentAction(for: reference, in: store.state, now: Date()) else { await store.refresh(); return .result() }
        if snooze { store.snooze(item, minutes: store.state.preferences?.snoozeMinutes ?? 10) }
        else { store.complete(item) }
        await store.refresh()
        #endif
        return .result()
    }
}
