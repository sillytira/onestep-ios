import XCTest
@testable import OneStepCore

final class ConfirmedRulesTests: XCTestCase {
 func testMonthlyRuleRetains31AcrossFebruary() {
 var c = Calendar(identifier:.gregorian);c.timeZone = TimeZone(secondsFromGMT:0)!
 func date(_ y:Int,_ m:Int,_ d:Int)->Date { c.date(from:DateComponents(year:y,month:m,day:d,hour:9))! }
 var t = TaskEntry(title:"Monthly",dueAt:date(2027,1,31),repeatRule:"monthly",repeatMonthDay:31,repeatAnchor:date(2027,1,31))
 XCTAssertEqual(RecurrenceRules.next(t,now:date(2027,1,31),calendar:c),date(2027,2,28))
 t.dueAt = date(2027,2,28)
 XCTAssertEqual(RecurrenceRules.next(t,now:date(2027,2,28),calendar:c),date(2027,3,31))
 }
 func testWeekdayIntervalAndInvalidRules() {
 var c = Calendar(identifier:.gregorian);c.timeZone = TimeZone(secondsFromGMT:0)!
 let due = c.date(from:DateComponents(year:2026,month:11,day:16,hour:8,minute:30))!
 var t = TaskEntry(title:"Weekdays",dueAt:due,repeatRule:"weekdays",repeatEvery:2,repeatWeekdays:[1,3])
 let now = c.date(from:DateComponents(year:2026,month:11,day:18,hour:9))!
 XCTAssertEqual(RecurrenceRules.next(t,now:now,calendar:c),c.date(from:DateComponents(year:2026,month:11,day:30,hour:8,minute:30)))
 t.repeatWeekdays = [0];XCTAssertFalse(RecurrenceRules.valid(t))
 }
 func testMergePreservesIndependentRecordsAndRequiresDeletionChoice() throws {
 let a:[String:Any] = ["id":"AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA","title":"Original"]
 let b:[String:Any] = ["id":"BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB","title":"Local"]
 let r:[String:Any] = ["id":"CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC","title":"Remote"]
 let base:[String:Any] = ["schemaVersion":1,"tasks":[a],"routines":[],"days":[]]
 var local = base,remote = base;local["tasks"] = [a,b];remote["tasks"] = [a,r]
 let merged = PlannerMerge.merge(base:base,local:local,remote:remote)
 XCTAssertTrue(merged.conflicts.isEmpty);XCTAssertEqual((merged.state["tasks"] as? [Any])?.count,3)
 local["tasks"] = [];remote["tasks"] = [["id":a["id"]!,"title":"Remote edit"]]
 let conflict = PlannerMerge.merge(base:base,local:local,remote:remote)
 XCTAssertEqual(conflict.conflicts.count,1);XCTAssertEqual((try conflict.resolved([0:false])["tasks"] as? [Any])?.count,0)
 XCTAssertEqual((try conflict.resolved([0:true])["tasks"] as? [[String:Any]])?.first?["title"] as? String,"Remote edit")
 }
}
