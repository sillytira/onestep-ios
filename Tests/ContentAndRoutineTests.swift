import XCTest
@testable import OneStepCore

final class ContentAndRoutineTests: XCTestCase {
    var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 8))! }
    func sample() -> ContentCatalog {
        ContentCatalog(format: "OneStepContent", schema: 1, revision: 1, minAppVersion: "0.5.0", message: "A small start", packs: [ContentPack(id: "test-pack", title: "Morning", description: "Optional", steps: [ContentStep(title: "Water", hour: 9, minute: 0, colorName: "blue")])])
    }
    func testCatalogRoundTripAndUnsupportedContent() throws {
        let good = sample()
        XCTAssertEqual(try ContentCatalog.decode(JSONEncoder().encode(good)), good)
        var bad = good; bad.schema = 2
        XCTAssertThrowsError(try bad.validated())
        bad = good; bad.minAppVersion = "0.6.0"
        XCTAssertThrowsError(try bad.validated())
        bad = good; bad.packs[0].steps[0].hour = 25
        XCTAssertThrowsError(try bad.validated())
        bad = good; bad.packs.append(bad.packs[0])
        XCTAssertThrowsError(try bad.validated())
        XCTAssertThrowsError(try ContentCatalog.decode(Data(repeating: 32, count: 65537)))
    }
    func testInstallPreservesDataAndIsIdempotent() throws {
        var state = PlannerState(); state.tasks = [TaskEntry(title: "Private")]
        state.routines = [RoutineStep(title: "My own", hour: 10, minute: 0, position: 0)]
        let catalog = sample(), first = catalog.installing(catalog.packs[0], in: state)
        XCTAssertEqual(first.tasks, state.tasks)
        XCTAssertEqual(first.routines.first, state.routines.first)
        XCTAssertEqual(first.routines.count, 2)
        XCTAssertEqual(catalog.installing(catalog.packs[0], in: first), first)
        XCTAssertEqual(try JSONDecoder().decode(PlannerState.self, from: JSONEncoder().encode(first)), first)
    }
    func testUndoOnlyTouchesTodayAndNeverTomorrowTemplate() {
        let step = RoutineStep(title: "Water", hour: 9, minute: 0, position: 0)
        var state = PlannerState(); state.routines = [step]
        state.days = [DailyRecord(stepID: step.id, day: PlannerRules.dayKey(now), title: step.title, status: .skipped, updatedAt: now), DailyRecord(stepID: step.id, day: "2026-11-11", title: step.title, status: .done, updatedAt: now)]
        let result = PlannerRules.undoRoutine(step.id, in: state, now: now)
        XCTAssertEqual(result.days.count, 1); XCTAssertEqual(result.days[0].day, "2026-11-11")
        XCTAssertEqual(result.routines, state.routines)
    }
    func testTodayReschedulingPreservesTaskDeadlineAndTomorrow() {
        let step = RoutineStep(title: "Water", hour: 9, minute: 0, position: 0)
        var state = PlannerState(); state.routines = [step]; state.tasks = [TaskEntry(title: "Letter", dueAt: now.addingTimeInterval(3600))]
        let result = PlannerRules.rescheduleRoutine(step.id, to: now.addingTimeInterval(7200), in: state, now: now)
        XCTAssertEqual(result.tasks, state.tasks); XCTAssertEqual(result.routines, state.routines)
        XCTAssertEqual(result.days.first?.snoozedUntil, now.addingTimeInterval(7200))
        XCTAssertEqual(PlannerRules.rescheduleRoutine(step.id, to: now.addingTimeInterval(86400), in: state, now: now), state)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        XCTAssertNil(PlannerRules.record(step, on: tomorrow, in: result))
    }
    func testSameTimeAlertsShareOneBannerAndCancelAfterCompletion() {
        var state = PlannerState()
        let due = now.addingTimeInterval(3600)
        state.tasks = [TaskEntry(title: "A", dueAt: due, reminderEnabled: true), TaskEntry(title: "B", dueAt: due, reminderEnabled: true)]
        let first = PlannerRules.reminderPlan(state, now: now)
        XCTAssertEqual(first.reminders.count, 2)
        XCTAssertTrue(first.reminders.allSatisfy { $0.title == "2 steps are ready" })
        state.tasks[0].completedAt = now
        XCTAssertTrue(PlannerRules.reminderPlan(state, now: now).reminders.allSatisfy { $0.title == "B" })
        state.tasks[1].completedAt = now
        XCTAssertTrue(PlannerRules.reminderPlan(state, now: now).reminders.isEmpty)
    }
}
