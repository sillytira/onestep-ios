import XCTest
@testable import OneStepCore

final class RewardBindingTests: XCTestCase {
    func testRewardBindingSurvivesTransferWithoutGivingAuthentication() throws {
        let user = UUID().uuidString
        var state = PlannerState()
        state.tasks = [TaskEntry(title: "Small next step", rewardPoints: 25, rewardAccountID: user)]
        let restored = try TransferDocument.decode(JSONEncoder().encode(TransferDocument(state: state))).state
        XCTAssertEqual(restored.tasks[0].rewardAccountID, user)
        XCTAssertEqual(restored.tasks[0].rewardPoints, 25)
        state.tasks[0].rewardPoints = 101
        XCTAssertThrowsError(try TransferDocument.decode(JSONEncoder().encode(TransferDocument(state: state))))
    }
    func testExpiredAndMissingLeasesBlockWhileAnActiveLeaseDoesNot() {
        let now = Date(timeIntervalSince1970: 1700000000)
        XCTAssertTrue(ShieldLeaseRules.shouldShield(enabled: true, expiry: nil, now: now))
        XCTAssertTrue(ShieldLeaseRules.shouldShield(enabled: true, expiry: now, now: now))
        XCTAssertFalse(ShieldLeaseRules.shouldShield(enabled: true, expiry: now.addingTimeInterval(1), now: now))
        XCTAssertFalse(ShieldLeaseRules.shouldShield(enabled: false, expiry: nil, now: now))
        XCTAssertGreaterThan(ShieldLeaseRules.monitorEnd(for: now), now)
    }
}
