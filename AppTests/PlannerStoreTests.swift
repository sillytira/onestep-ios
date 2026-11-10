import XCTest
@testable import OneStep

@MainActor
final class PlannerStoreTests: XCTestCase {
    func testSaveEditCompleteAndReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        let store = try PlannerStore(storeURL: url)
        XCTAssertTrue(store.saveTask(id: nil, title: "  Water plants  ", notes: "Kitchen", dueAt: nil, reminder: false))
        let id = try XCTUnwrap(store.state.tasks.first?.id)
        XCTAssertTrue(store.saveTask(id: id, title: "Water plants", notes: "Living room", dueAt: nil, reminder: false))
        store.complete(PlannerRules.taskAction(store.state.tasks[0]))
        let reopened = try PlannerStore(storeURL: url)
        XCTAssertEqual(reopened.state.tasks.first?.id, id)
        XCTAssertEqual(reopened.state.tasks.first?.notes, "Living room")
        XCTAssertNotNil(reopened.state.tasks.first?.completedAt)
    }

    func testDoneAndSkipHaveIndependentDatedRecords() async throws {
        let store = try PlannerStore(inMemory: true)
        XCTAssertTrue(store.saveRoutine(id: nil, title: "Water", time: Date()))
        XCTAssertTrue(store.saveRoutine(id: nil, title: "Breakfast", time: Date()))
        let first = PlannerRules.routineAction(store.state.routines[0], on: Date(), state: store.state)
        let second = PlannerRules.routineAction(store.state.routines[1], on: Date(), state: store.state)
        store.complete(first)
        store.complete(second, skip: true)
        XCTAssertEqual(store.state.days.count, 2)
        XCTAssertEqual(store.state.days.first(where: { $0.stepID == first.sourceID })?.status, .done)
        XCTAssertEqual(store.state.days.first(where: { $0.stepID == second.sourceID })?.status, .skipped)
        store.deleteRoutine(store.state.routines[0])
        XCTAssertEqual(store.state.days.count, 2, "Deleting a template must preserve its history")
    }

    func testBlankTitlesAreRejectedAndSnoozePersists() async throws {
        let store = try PlannerStore(inMemory: true)
        XCTAssertFalse(store.saveTask(id: nil, title: "   ", notes: "", dueAt: nil, reminder: false))
        XCTAssertTrue(store.saveTask(id: nil, title: "A task", notes: "", dueAt: nil, reminder: false))
        let item = PlannerRules.taskAction(store.state.tasks[0])
        store.snooze(item)
        XCTAssertNotNil(store.state.tasks[0].snoozedUntil)
        XCTAssertNil(PlannerRules.nextAction(store.state, now: Date()))
    }
}
