import XCTest
@testable import OneStepCore

final class XPTests: XCTestCase {
    func testTaskOutboxIsAccountBoundIdempotentAndPortable() throws {
        let user = UUID().uuidString
        let task = TaskEntry(title: "One small task")
        var state = PlannerState(); state.tasks = [task]
        let action = PlannerRules.taskAction(task)
        state = XPRules.recording(action, accountID:user, in:state)
        state = XPRules.recording(action, accountID:user.lowercased(), in:state)
        XCTAssertEqual(state.xpCompletions?.count,1)
        XCTAssertEqual(state.xpCompletions?.first?.accountID,user.lowercased())
        let restored = try TransferDocument.decode(JSONEncoder().encode(TransferDocument(state:state))).state
        XCTAssertEqual(restored.xpCompletions,state.xpCompletions)
        XCTAssertNil(XPRules.recording(action,accountID:nil,in:PlannerState()).xpCompletions)
    }
    func testRoutineDayHasOneAwardAndTomorrowHasItsOwn() {
        let user = UUID().uuidString; let step = UUID()
        let item = ActionItem(kind:.routine,sourceID:step,title:"Brush teeth",notes:"",day:"2026-11-12")
        var state = XPRules.recording(item,accountID:user,in:PlannerState())
        state = XPRules.recording(item,accountID:user,in:state)
        var tomorrow = item; tomorrow.day = "2026-11-13"
        state = XPRules.recording(tomorrow,accountID:user,in:state)
        XCTAssertEqual(state.xpCompletions?.count,2)
        XCTAssertTrue(state.xpCompletions?.allSatisfy(\.valid) == true)
    }
}
