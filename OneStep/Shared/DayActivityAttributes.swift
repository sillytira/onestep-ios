import ActivityKit
import Foundation

struct DayActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var isRoutine: Bool
        var colorName: String
        var completedSteps: Int
        var totalSteps: Int
        var snapshotAt: Date
        var scheduledAt: Date?
        var timerStartedAt: Date?
        var timerEndsAt: Date?
        var actionID: String?
    }
    var dayLabel: String
    var startedAt: Date
}
