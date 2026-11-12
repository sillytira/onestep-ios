import Foundation
import WidgetKit

struct NextActionSnapshot: Codable {
    var title: String
    var at: Date
}
enum WidgetSnapshotStore {
    static var folder: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.meow.tira.onestep") }
    static func read() -> NextActionSnapshot? {
        guard let url = folder?.appendingPathComponent("next-action.json"), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(NextActionSnapshot.self, from: data), Calendar.current.isDateInToday(value.at) else { return nil }
        return value
    }
    #if ONESTEP_APP
    @MainActor static func publish(_ state: PlannerState) {
        guard ScreenTimeShared.enabledBuild, let url = folder?.appendingPathComponent("next-action.json") else { return }
        let title = UserDefaults.standard.bool(forKey: "shareWidgetTitles") ? (PlannerRules.nextAction(state, now: Date())?.title ?? "A little breathing room") : "Open OneStep for your next action"
        if let data = try? JSONEncoder().encode(NextActionSnapshot(title: title, at: Date())) { try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); WidgetCenter.shared.reloadTimelines(ofKind: "OneStepNextAction") }
    }
    #endif
}
