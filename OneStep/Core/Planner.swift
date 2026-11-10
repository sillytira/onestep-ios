import Foundation

struct TaskEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var notes = ""
    var createdAt = Date()
    var dueAt: Date?
    var reminderEnabled = false
    var completedAt: Date?
    var snoozedUntil: Date?
}

struct RoutineStep: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var hour: Int
    var minute: Int
    var position: Int
}

enum DailyStatus: String, Codable { case done, skipped }

struct DailyRecord: Identifiable, Codable, Equatable {
    var id: String { "\(stepID.uuidString).\(day)" }
    var stepID: UUID
    var day: String
    var title: String
    var status: DailyStatus?
    var snoozedUntil: Date?
    var updatedAt: Date
}

struct PlannerState: Codable, Equatable {
    var schemaVersion = 1
    var tasks: [TaskEntry] = []
    var routines: [RoutineStep] = []
    var days: [DailyRecord] = []
}

struct ActionItem: Identifiable, Equatable {
    enum Kind: String, Codable { case task, routine }
    var kind: Kind
    var sourceID: UUID
    var title: String
    var notes: String
    var scheduledAt: Date?
    var day: String?
    var id: String { "\(kind.rawValue).\(sourceID.uuidString).\(day ?? "")" }
}

struct PlannedReminder: Identifiable, Equatable {
    var id: String
    var title: String
    var body: String
    var fireAt: Date
    var item: ActionItem
}

struct ReminderPlan {
    var reminders: [PlannedReminder]
    var omittedCount: Int
    /// End of the continuous scheduling window, not the time of the last alert.
    var coverageUntil: Date
}

enum PlannerRules {
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func scheduledTime(_ step: RoutineStep, on date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: step.hour, minute: step.minute, second: 0, of: date,
                      matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)!
    }

    static func record(_ step: RoutineStep, on date: Date, in state: PlannerState,
                       calendar: Calendar = .current) -> DailyRecord? {
        let key = dayKey(date, calendar: calendar)
        return state.days.first { $0.stepID == step.id && $0.day == key }
    }

    static func taskAction(_ task: TaskEntry) -> ActionItem {
        ActionItem(kind: .task, sourceID: task.id, title: task.title, notes: task.notes,
                   scheduledAt: task.snoozedUntil ?? task.dueAt)
    }

    static func routineAction(_ step: RoutineStep, on date: Date, state: PlannerState,
                              calendar: Calendar = .current) -> ActionItem {
        let entry = record(step, on: date, in: state, calendar: calendar)
        return ActionItem(kind: .routine, sourceID: step.id, title: step.title, notes: "Daily routine",
                          scheduledAt: entry?.snoozedUntil ?? scheduledTime(step, on: date, calendar: calendar),
                          day: dayKey(date, calendar: calendar))
    }

    static func availableActions(_ state: PlannerState, now: Date,
                                 calendar: Calendar = .current) -> [ActionItem] {
        let tasks = state.tasks.filter { $0.completedAt == nil && ($0.snoozedUntil == nil || $0.snoozedUntil! <= now) }
            .sorted { $0.createdAt < $1.createdAt }.map(taskAction)
        let routines = state.routines.sorted { $0.position < $1.position }.compactMap { step -> ActionItem? in
            let entry = record(step, on: now, in: state, calendar: calendar)
            guard entry?.status == nil, entry?.snoozedUntil == nil || entry!.snoozedUntil! <= now else { return nil }
            return routineAction(step, on: now, state: state, calendar: calendar)
        }
        return tasks + routines
    }

    static func nextAction(_ state: PlannerState, now: Date,
                           calendar: Calendar = .current) -> ActionItem? {
        let items = availableActions(state, now: now, calendar: calendar)
        // A due action comes before an unscheduled task; future routines wait their turn.
        return items.first { $0.scheduledAt != nil && $0.scheduledAt! <= now }
            ?? items.first { $0.kind == .task && $0.scheduledAt == nil }
            ?? items.sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }.first
    }

    static func reminderPlan(_ state: PlannerState, now: Date, calendar: Calendar = .current,
                             limit: Int = 60, horizonDays: Int = 14) -> ReminderPlan {
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: calendar.startOfDay(for: now))!
        var candidates: [PlannedReminder] = []
        func append(_ item: ActionItem, at date: Date, suffix: String, followup: Bool = false) {
            guard date > now else { return } // Never replay a backlog of missed alerts.
            candidates.append(PlannedReminder(id: "\(item.id).\(suffix)", title: item.title,
                body: followup ? "Ready for this step? Open OneStep to do it, snooze, or skip today."
                               : "One thing at a time. Open OneStep when you're ready.",
                fireAt: date, item: item))
        }
        for task in state.tasks where task.completedAt == nil {
            let item = taskAction(task)
            if let snooze = task.snoozedUntil {
                append(item, at: snooze, suffix: "snooze")
            } else if task.reminderEnabled, let due = task.dueAt {
                append(item, at: due, suffix: "due")
                append(item, at: due.addingTimeInterval(600), suffix: "followup", followup: true)
            }
        }
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: day)!
            for step in state.routines {
                let entry = record(step, on: day, in: state, calendar: calendar)
                guard entry?.status == nil else { continue }
                let item = routineAction(step, on: day, state: state, calendar: calendar)
                if let snooze = entry?.snoozedUntil {
                    append(item, at: snooze, suffix: "snooze")
                } else {
                    let due = scheduledTime(step, on: day, calendar: calendar)
                    append(item, at: due, suffix: "due")
                    let followup = due.addingTimeInterval(600)
                    // A late-night step must not alert as part of yesterday's routine.
                    if followup < endOfDay { append(item, at: followup, suffix: "followup", followup: true) }
                }
            }
        }
        candidates.sort { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
        let selected = Array(candidates.prefix(max(0, limit)))
        let firstOmitted = candidates.dropFirst(max(0, limit)).first?.fireAt
        return ReminderPlan(reminders: selected, omittedCount: max(0, candidates.count - selected.count),
                            coverageUntil: min(horizon, firstOmitted?.addingTimeInterval(-1) ?? horizon))
    }
}
