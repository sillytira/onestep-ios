import ActivityKit
import Foundation

@MainActor
final class DayActivityController {
    private var activities: [Activity<DayActivityAttributes>] {
        Activity<DayActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }
    var isRunning: Bool { !activities.isEmpty }

    static func content(_ state: PlannerState, now: Date) -> DayActivityAttributes.ContentState {
        let next = PlannerRules.nextAction(state, now: now)
        let today = PlannerRules.dayKey(now)
        let done = state.routines.filter { step in state.days.contains { $0.stepID == step.id && $0.day == today && $0.status == .done } }.count
        let timer = state.focusSession.flatMap { session in
            session.pausedRemaining != nil || PlannerRules.currentAction(for: session.action, in: state, now: now) == nil ? nil : session
        }
        return DayActivityAttributes.ContentState(
            title: next?.title ?? "A little breathing room",
            subtitle: next?.kind == .routine ? "Daily routine" : "One thing at a time",
            isRoutine: next?.kind == .routine,
            colorName: next?.colorName ?? (next?.kind == .routine ? "violet" : "blue"),
            completedSteps: done, totalSteps: state.routines.count, snapshotAt: now,
            scheduledAt: next?.scheduledAt,
            timerStartedAt: timer?.startedAt, timerEndsAt: timer?.endsAt, actionID: next?.id)
    }

    private func activityContent(_ state: PlannerState, now: Date) -> ActivityContent<DayActivityAttributes.ContentState> {
        let snapshot = Self.content(state, now: now)
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        let nextChange = [snapshot.scheduledAt, snapshot.timerEndsAt, midnight].compactMap { $0 }.filter { $0 > now }.min() ?? midnight
        return ActivityContent(state: snapshot, staleDate: nextChange)
    }

    func start(_ state: PlannerState) throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw ActivityError.disabled }
        guard !isRunning else { return }
        let now = Date()
        _ = try Activity.request(attributes: DayActivityAttributes(dayLabel: now.formatted(.dateTime.weekday(.wide)), startedAt: now),
                                 content: activityContent(state, now: now), pushType: nil)
    }

    func update(_ state: PlannerState) async {
        for activity in activities {
            // A day session is never silently carried into tomorrow.
            if !Calendar.current.isDateInToday(activity.attributes.startedAt) {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.update(activityContent(state, now: Date()))
            }
        }
    }

    func stop() async {
        for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    enum ActivityError: LocalizedError {
        case disabled
        var errorDescription: String? { "Live Activities are off. Enable them for OneStep in iPhone Settings, then try again." }
    }
}
