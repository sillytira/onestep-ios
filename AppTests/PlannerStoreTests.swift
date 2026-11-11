import XCTest
import CryptoKit
@testable import OneStep

@MainActor
final class PlannerStoreTests: XCTestCase {
    func testTransferCipherMatchesPortableWireVector() throws {
        let raw = Data((0..<32).map { UInt8($0) })
        let wire = Data(base64Encoded: "AAECAwQFBgcICQoLCGyzSLGAsjv5M/blwo8dH+zM+Qx4xwiOhXAxOFLt8mY=")!
        let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: wire), using: SymmetricKey(data: raw))
        XCTAssertEqual(String(data: clear, encoding: .utf8), "OneStep transfer")
        XCTAssertFalse(LocalTransfer.isPrivateIPv4("8.8.8.8"))
        XCTAssertTrue(LocalTransfer.isPrivateIPv4("192.168.1.5"))
        XCTAssertFalse(OnlineAccount.isPublicKey("sb_secret_never-use-in-a-client"))
    }
    func testRepeatCreatesOneFutureTaskAndUndoRemovesIt() throws {
        let store = try PlannerStore(inMemory: true)
        XCTAssertTrue(store.saveTask(id: nil, title: "Water", notes: "", dueAt: Date().addingTimeInterval(-86400), reminder: true, repeatRule: "daily", steps: ["Fill can"]))
        let task = store.state.tasks[0]
        store.complete(PlannerRules.taskAction(task))
        XCTAssertEqual(store.state.tasks.count, 2)
        XCTAssertGreaterThan(store.state.tasks.last!.dueAt!, Date())
        store.undoTask(task)
        XCTAssertEqual(store.state.tasks.count, 1)
        XCTAssertNil(store.state.tasks[0].completedAt)
    }

    func testSnapshotImportAndTimerPauseLeaveDeadlinesAlone() throws {
        let store = try PlannerStore(inMemory: true)
        let due = Date().addingTimeInterval(7200)
        XCTAssertTrue(store.saveTask(id: nil, title: "Read", notes: "", dueAt: due, reminder: true))
        let item = PlannerRules.taskAction(store.state.tasks[0])
        XCTAssertTrue(store.startFocus(item, until: Date().addingTimeInterval(900)))
        store.togglePause()
        XCTAssertNotNil(store.state.focusSession?.pausedRemaining)
        XCTAssertEqual(store.state.tasks[0].dueAt, due)
        let backup = try TransferDocument.decode(store.exportData())
        XCTAssertTrue(store.importDocument(backup))
        XCTAssertEqual(store.state.tasks[0].dueAt, due)
        XCTAssertNil(store.state.focusSession)
    }
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

    func testFocusClearsOnCompletionAndSnooze() async throws {
        let store = try PlannerStore(inMemory: true)
        XCTAssertTrue(store.saveTask(id: nil, title: "Focus", notes: "", dueAt: nil, reminder: false, colorName: "coral"))
        let item = PlannerRules.taskAction(store.state.tasks[0])
        XCTAssertTrue(store.startFocus(item, until: Date().addingTimeInterval(300)))
        XCTAssertEqual(store.state.focusSession?.action.colorName, "coral")
        store.snooze(item)
        XCTAssertNil(store.state.focusSession)
        XCTAssertTrue(store.startFocus(item, until: Date().addingTimeInterval(300)))
        store.complete(item)
        XCTAssertNil(store.state.focusSession)
    }

    func testLiveActivitySnapshotUsesCurrentTitleColorAndRoutineProgress() async throws {
        let store = try PlannerStore(inMemory: true)
        XCTAssertTrue(store.saveTask(id: nil, title: "Focus", notes: "", dueAt: nil, reminder: false, colorName: "rose"))
        XCTAssertTrue(store.saveRoutine(id: nil, title: "Water", time: Date(), colorName: "mint"))
        let item = PlannerRules.taskAction(store.state.tasks[0])
        XCTAssertTrue(store.startFocus(item, until: Date().addingTimeInterval(300)))
        let step = PlannerRules.routineAction(store.state.routines[0], on: Date(), state: store.state)
        store.complete(step)
        let snapshot = DayActivityController.content(store.state, now: Date())
        XCTAssertEqual(snapshot.title, "Focus")
        XCTAssertEqual(snapshot.colorName, "rose")
        XCTAssertEqual(snapshot.completedSteps, 1)
        XCTAssertEqual(snapshot.totalSteps, 1)
        XCTAssertNotNil(snapshot.timerEndsAt)
    }
}
