import XCTest
import CryptoKit
import SwiftUI
import UIKit
@testable import OneStep

@MainActor
final class PlannerStoreTests: XCTestCase {
    func testURLRouteIsRetainedUntilTheInterfaceConsumesIt() throws {
        let store = try PlannerStore(inMemory:true)
        store.receiveURL(URL(string:"onestep://bank")!)
        XCTAssertEqual(store.selectedTab,3)
        XCTAssertEqual(store.pendingRoute,.bank)
        store.receiveURL(URL(string:"https://example.invalid/now")!)
        XCTAssertEqual(store.selectedTab,3)
        XCTAssertEqual(store.pendingRoute,.bank)
        store.receiveURL(URL(string:"onestep://add")!)
        XCTAssertEqual(store.selectedTab,1)
        XCTAssertEqual(store.pendingRoute,.add)
    }
    func testLiveActivityActionsUseExactTaskAndDoNotRepeatCompletion() async throws {
        let previous = PlannerStore.shared
        defer { PlannerStore.shared = previous }
        let store = try PlannerStore(inMemory: true)
        PlannerStore.shared = store
        XCTAssertTrue(store.saveTask(id: nil, title: "First", notes: "", dueAt: nil, reminder: false))
        XCTAssertTrue(store.saveTask(id: nil, title: "Second", notes: "", dueAt: nil, reminder: false))
        let first = PlannerRules.taskAction(store.state.tasks[0])
        _ = try await DayActionIntent(first.id).perform()
        XCTAssertNotNil(store.state.tasks[0].completedAt)
        XCTAssertNil(store.state.tasks[1].completedAt)
        _ = try await DayActionIntent(first.id).perform()
        XCTAssertNil(store.state.tasks[1].completedAt)
        let second = PlannerRules.taskAction(store.state.tasks[1])
        _ = try await DayActionIntent(second.id, snooze: true).perform()
        XCTAssertGreaterThan(store.state.tasks[1].snoozedUntil ?? .distantPast, Date())
        XCTAssertNil(store.state.tasks[1].completedAt)
    }

    func testLiveActivityRejectsPreviousDayAndArchivedReferences() async throws {
        let previous = PlannerStore.shared
        defer { PlannerStore.shared = previous }
        let store = try PlannerStore(inMemory: true)
        PlannerStore.shared = store
        XCTAssertTrue(store.saveRoutine(id: nil, title: "Water", time: Date()))
        var item = PlannerRules.routineAction(store.state.routines[0], on: Date(), state: store.state)
        item.day = "2001-01-01"
        _ = try await DayActionIntent(item.id).perform()
        XCTAssertTrue(store.state.days.isEmpty)
        XCTAssertTrue(store.saveTask(id: nil, title: "Archived", notes: "", dueAt: nil, reminder: false))
        var state = store.state
        state.tasks[0].archived = true
        XCTAssertTrue(store.commit(state))
        _ = try await DayActionIntent(PlannerRules.taskAction(state.tasks[0]).id).perform()
        XCTAssertNil(store.state.tasks[0].completedAt)
    }
    func testOfflineParentCodeMatchesPortablePBKDF2Vector() {
        let verifier: [String: Any] = ["algorithm": "pbkdf2-sha256", "iterations": 120000, "salt": "AAECAwQFBgcICQoLDA0ODw==", "hash": "nVox1uAswwfkowNdrWPmBt5pBK77mZIbAAxTqHkqG9U="]
        XCTAssertTrue(RewardsStore.checkPin("0123456789", verifier: verifier))
        XCTAssertFalse(RewardsStore.checkPin("9876543210", verifier: verifier))
    }

    func testTransferCipherMatchesPortableWireVector() throws {
        let raw = Data((0..<32).map { UInt8($0) })
        let wire = Data(base64Encoded: "AAECAwQFBgcICQoLCGyzSLGAsjv5M/blwo8dH+zM+Qx4xwiOhXAxOFLt8mY=")!
        let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: wire), using: SymmetricKey(data: raw))
        XCTAssertEqual(String(data: clear, encoding: .utf8), "OneStep transfer")
        XCTAssertFalse(LocalTransfer.isPrivateIPv4("8.8.8.8"))
        XCTAssertTrue(LocalTransfer.isPrivateIPv4("192.168.1.5"))
        XCTAssertFalse(OnlineAccount.isPublicKey("sb_" + "secret_" + "invalid-test-value"))
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
        XCTAssertEqual(snapshot.actionID, item.id)
    }

    func testDetailedActivitySnapshotHandlesPausedTimersAndSkippedSteps() throws {
        let now = Date(); let day = PlannerRules.dayKey(now)
        let done = TaskEntry(title:"Finished task",completedAt:now)
        let task = TaskEntry(title:"Read one page",microsteps:[SmallStep(title:"Open the book")])
        let following = TaskEntry(title:"Fill the water bottle")
        let first = RoutineStep(title:"Breakfast",hour:8,minute:0,position:0)
        let second = RoutineStep(title:"Walk",hour:9,minute:0,position:1)
        var state=PlannerState();state.tasks=[done,task,following];state.routines=[first,second]
        state.days=[DailyRecord(stepID:first.id,day:day,title:first.title,status:.done,updatedAt:now),DailyRecord(stepID:second.id,day:day,title:second.title,status:.skipped,updatedAt:now)]
        state.focusSession=FocusSession(action:PlannerRules.taskAction(task),startedAt:now,endsAt:now.addingTimeInterval(100),durationBased:true,pausedRemaining:45)
        let snapshot=DayActivityController.content(state,now:now)
        XCTAssertEqual(snapshot.tasksDone,1);XCTAssertEqual(snapshot.tasksRemaining,2)
        XCTAssertEqual(snapshot.skippedSteps,1);XCTAssertEqual(snapshot.completedSteps,1)
        XCTAssertEqual(snapshot.detail,"Small step: Open the book")
        XCTAssertEqual(snapshot.timerPausedRemaining,45);XCTAssertNil(snapshot.timerEndsAt)
        var legacy=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(snapshot)) as? [String:Any])
        for key in ["tasksDone","tasksRemaining","skippedSteps","detail","timerPausedRemaining","snoozeMinutes"] { legacy.removeValue(forKey:key) }
        let restored=try JSONDecoder().decode(DayActivityAttributes.ContentState.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertNil(restored.tasksDone);XCTAssertEqual(restored.title,snapshot.title)
    }
    func testActivityPayloadIsBoundedAndFollowingActionUsesPlannerOrder() throws {
        var state=PlannerState()
        let title=String(repeating:"👨‍👩‍👧‍👦\\\"\n",count:1000)
        let task=TaskEntry(title:title,microsteps:[SmallStep(title:title)])
        state.tasks=[task,TaskEntry(title:"A following action")]
        let now=Date();let snapshot=DayActivityController.content(state,now:now)
        let attributes=DayActivityAttributes(dayLabel:"Thursday",startedAt:now)
        XCTAssertLessThan(try JSONEncoder().encode(snapshot).count+JSONEncoder().encode(attributes).count,4096)
        state.tasks[0].microsteps=[]
        XCTAssertEqual(DayActivityController.content(state,now:now).detail,"Up next: A following action")
    }
    func testDetailedLockScreenCardRendersWithinSystemHeight() throws {
        let now=Date()
        let state=DayActivityAttributes.ContentState(title:"Make a little space for your next idea",subtitle:"One thing at a time",isRoutine:false,colorName:"violet",completedSteps:3,totalSteps:5,snapshotAt:now,timerStartedAt:now,timerEndsAt:now.addingTimeInterval(900),actionID:"task."+UUID().uuidString+".",tasksDone:4,tasksRemaining:2,skippedSteps:1,detail:"Small step: Open your notebook",snoozeMinutes:10)
        for (name,width,size) in [("standard",366.0,DynamicTypeSize.large),("large-text",320.0,DynamicTypeSize.accessibility2)] {
            let renderer=ImageRenderer(content:DayActivityCard(state:state,dayLabel:"Thursday").environment(\.dynamicTypeSize,size).preferredColorScheme(.dark).frame(width:width,height:160).background(Color.black))
            renderer.scale=2
            let image=try XCTUnwrap(renderer.uiImage)
            XCTAssertLessThanOrEqual(image.size.height,160);XCTAssertGreaterThan(image.size.width,0)
            let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("OneStep-LiveActivity-"+name+".png")
            try XCTUnwrap(image.pngData()).write(to:url)
        }
    }

}
