import XCTest
@testable import OneStepCore

final class PlannerRulesTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var morning: Date { date("2026-11-10T08:00:00Z") }

    func testDailyCompletionDoesNotCompleteTomorrow() {
        let step = RoutineStep(title: "Water", hour: 9, minute: 0, position: 0)
        var state = PlannerState()
        state.routines = [step]
        state.days = [DailyRecord(stepID: step.id, day: "2026-11-10", title: step.title, status: .done, updatedAt: morning)]
        let plan = PlannerRules.reminderPlan(state, now: morning, calendar: utc)
        XCTAssertFalse(plan.reminders.contains { $0.item.day == "2026-11-10" })
        XCTAssertEqual(plan.reminders.filter { $0.item.day == "2026-11-11" }.count, 2)
        XCTAssertEqual(state.days.count, 1)
    }

    func testSkippedStepCancelsDueAndFollowup() {
        let step = RoutineStep(title: "Water", hour: 9, minute: 0, position: 0)
        var state = PlannerState()
        state.routines = [step]
        state.days = [DailyRecord(stepID: step.id, day: "2026-11-10", title: step.title, status: .skipped, updatedAt: morning)]
        XCTAssertFalse(PlannerRules.reminderPlan(state, now: morning, calendar: utc).reminders.contains { $0.item.day == "2026-11-10" })
    }

    func testSnoozeReplacesBothAlertsWithOne() {
        let step = RoutineStep(title: "Water", hour: 9, minute: 0, position: 0)
        var state = PlannerState()
        state.routines = [step]
        state.days = [DailyRecord(stepID: step.id, day: "2026-11-10", title: step.title,
                                  snoozedUntil: date("2026-11-10T09:20:00Z"), updatedAt: morning)]
        let today = PlannerRules.reminderPlan(state, now: morning, calendar: utc).reminders.filter { $0.item.day == "2026-11-10" }
        XCTAssertEqual(today.count, 1)
        XCTAssertTrue(today[0].id.hasSuffix("snooze"))
    }

    func testCompletedTaskHasNoAlerts() {
        var state = PlannerState()
        state.tasks = [TaskEntry(title: "Send letter", dueAt: morning.addingTimeInterval(3600), reminderEnabled: true, completedAt: morning)]
        XCTAssertTrue(PlannerRules.reminderPlan(state, now: morning, calendar: utc).reminders.isEmpty)
    }

    func testTaskSnoozeHasNoFollowupAndDoesNotMoveDeadline() {
        let due = morning.addingTimeInterval(3600)
        let snooze = morning.addingTimeInterval(7200)
        var state = PlannerState()
        state.tasks = [TaskEntry(title: "Letter", dueAt: due, reminderEnabled: true, snoozedUntil: snooze)]
        let plan = PlannerRules.reminderPlan(state, now: morning, calendar: utc)
        XCTAssertEqual(plan.reminders.count, 1)
        XCTAssertEqual(plan.reminders[0].fireAt, snooze)
        XCTAssertEqual(state.tasks[0].dueAt, due)
    }

    func testNoReplayOfMissedNotifications() {
        var state = PlannerState()
        state.tasks = [TaskEntry(title: "Old task", dueAt: morning.addingTimeInterval(-3600), reminderEnabled: true)]
        state.routines = [RoutineStep(title: "Old step", hour: 6, minute: 0, position: 0)]
        let plan = PlannerRules.reminderPlan(state, now: morning, calendar: utc)
        XCTAssertTrue(plan.reminders.allSatisfy { $0.fireAt > morning })
        XCTAssertFalse(plan.reminders.contains { $0.item.day == "2026-11-10" })
        XCTAssertFalse(plan.reminders.contains { $0.item.kind == .task })
    }

    func testCapacityKeepsNearestAlertsAndReportsCoverage() {
        var state = PlannerState()
        for hour in 0..<8 { state.routines.append(RoutineStep(title: "Step \(hour)", hour: hour + 9, minute: 0, position: hour)) }
        let plan = PlannerRules.reminderPlan(state, now: morning, calendar: utc, limit: 3)
        XCTAssertEqual(plan.reminders.count, 3)
        XCTAssertGreaterThan(plan.omittedCount, 0)
        XCTAssertLessThan(plan.coverageUntil, date("2026-11-10T10:10:00Z"))
        XCTAssertEqual(plan.reminders.map(\.fireAt), plan.reminders.map(\.fireAt).sorted())
    }

    func testNextActionSkipsSnoozedAndCompletedItems() {
        var state = PlannerState()
        state.tasks = [TaskEntry(title: "Finished", completedAt: morning),
                       TaskEntry(title: "Later", snoozedUntil: morning.addingTimeInterval(600)), TaskEntry(title: "Available")]
        XCTAssertEqual(PlannerRules.nextAction(state, now: morning, calendar: utc)?.title, "Available")
    }

    func testDayKeyUsesSuppliedTimeZone() {
        var berlin = utc
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let beforeMidnightUTC = date("2026-11-10T23:30:00Z")
        XCTAssertEqual(PlannerRules.dayKey(beforeMidnightUTC, calendar: utc), "2026-11-10")
        XCTAssertEqual(PlannerRules.dayKey(beforeMidnightUTC, calendar: berlin), "2026-11-11")
    }

    func testSpringForwardDoesNotDropDailyStep() {
        var berlin = utc
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let day = date("2027-03-28T00:00:00Z")
        let step = RoutineStep(title: "Early", hour: 2, minute: 30, position: 0)
        let scheduled = PlannerRules.scheduledTime(step, on: day, calendar: berlin)
        XCTAssertEqual(PlannerRules.dayKey(scheduled, calendar: berlin), "2027-03-28")
        XCTAssertEqual(berlin.component(.hour, from: scheduled), 3)
    }

    func testLateRoutineDoesNotFollowUpTomorrow() {
        var state = PlannerState()
        state.routines = [RoutineStep(title: "Sleep", hour: 23, minute: 55, position: 0)]
        let today = PlannerRules.reminderPlan(state, now: morning, calendar: utc).reminders.filter { $0.item.day == "2026-11-10" }
        XCTAssertEqual(today.count, 1)
    }

    func testPersistenceDocumentRoundTripRetainsIDsAndHistory() throws {
        let step = RoutineStep(title: "Water", hour: 9, minute: 0, position: 0)
        var state = PlannerState()
        state.tasks = [TaskEntry(title: "A task", notes: "A note", dueAt: morning, reminderEnabled: true)]
        state.routines = [step]
        state.days = [DailyRecord(stepID: step.id, day: "2026-11-10", title: step.title, status: .done, updatedAt: morning)]
        let restored = try JSONDecoder().decode(PlannerState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored, state)
    }

    func testVersionOneDocumentWithoutNewFieldsStillLoads() throws {
        var oldState = PlannerState()
        oldState.tasks = [TaskEntry(title: "Keep my task", colorName: "coral")]
        oldState.routines = [RoutineStep(title: "Keep my routine", hour: 9, minute: 0, position: 0, colorName: "rose")]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(oldState)) as? [String: Any])
        json.removeValue(forKey: "focusSession")
        var tasks = try XCTUnwrap(json["tasks"] as? [[String: Any]])
        tasks[0].removeValue(forKey: "colorName")
        json["tasks"] = tasks
        var routines = try XCTUnwrap(json["routines"] as? [[String: Any]])
        routines[0].removeValue(forKey: "colorName")
        json["routines"] = routines
        let restored = try JSONDecoder().decode(PlannerState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.tasks[0].id, oldState.tasks[0].id)
        XCTAssertEqual(restored.routines[0].id, oldState.routines[0].id)
        XCTAssertNil(restored.tasks[0].colorName)
        XCTAssertNil(restored.routines[0].colorName)
        XCTAssertNil(restored.focusSession)
    }

    func testTimerGetsReservedNotificationCapacity() {
        let task = TaskEntry(title: "Focus here", dueAt: morning.addingTimeInterval(3600), reminderEnabled: true)
        var state = PlannerState()
        state.tasks = [task]
        state.focusSession = FocusSession(action: PlannerRules.taskAction(task), startedAt: morning, endsAt: morning.addingTimeInterval(900))
        let plan = PlannerRules.reminderPlan(state, now: morning, calendar: utc, limit: 1)
        XCTAssertEqual(plan.reminders.count, 1)
        XCTAssertTrue(plan.reminders[0].id.hasPrefix("focus."))
        XCTAssertEqual(plan.omittedCount, 2)
    }

    func testTimerExpiryDoesNotReplayAndCompletedItemInvalidatesTimer() {
        var task = TaskEntry(title: "Focus here")
        var state = PlannerState()
        state.tasks = [task]
        state.focusSession = FocusSession(action: PlannerRules.taskAction(task), startedAt: morning.addingTimeInterval(-900), endsAt: morning.addingTimeInterval(-1))
        XCTAssertTrue(PlannerRules.reminderPlan(state, now: morning, calendar: utc).reminders.isEmpty)
        XCTAssertEqual(PlannerRules.nextAction(state, now: morning, calendar: utc)?.sourceID, task.id)
        task.completedAt = morning
        state.tasks = [task]
        XCTAssertNil(PlannerRules.nextAction(state, now: morning, calendar: utc))
    }

    func testTimerAndDueAtSameInstantProduceSingleExpiryAlert() {
        let deadline = morning.addingTimeInterval(900)
        let task = TaskEntry(title: "Focus here", dueAt: deadline, reminderEnabled: true)
        var state = PlannerState()
        state.tasks = [task]
        state.focusSession = FocusSession(action: PlannerRules.taskAction(task), startedAt: morning, endsAt: deadline)
        let plan = PlannerRules.reminderPlan(state, now: morning, calendar: utc)
        XCTAssertEqual(plan.reminders.filter { $0.fireAt == deadline }.count, 1)
        XCTAssertTrue(plan.reminders.contains { $0.id.hasPrefix("focus.") })
    }
}
