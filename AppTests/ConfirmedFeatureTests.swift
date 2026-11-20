import XCTest
import SwiftUI
import UIKit
@testable import OneStep

private actor SessionTransportFixture {
    var calls = 0
    let failures: [Int]
    init(_ failures: [Int]) { self.failures = failures }
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        calls += 1
        let refresh = request.url!.absoluteString.contains("grant_type=refresh_token")
        let status = refresh && calls <= failures.count ? failures[calls-1] : 200
        let value: [String:Any]
        if status != 200 { value = ["msg":"no refresh token","error":"invalid_grant"] }
        else if refresh { value = ["access_token":"synthetic-new-access","refresh_token":"synthetic-rotated-refresh","expires_in":3600,"user":["id":"synthetic-child","email":"child@example.invalid"]] }
        else { value = ["ok":true] }
        return (try JSONSerialization.data(withJSONObject:value),HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!)
    }
}

@MainActor final class SessionRecoveryTests: XCTestCase {
    func saved(_ refresh: String = "synthetic-old-refresh") -> [String:Any] {
        ["access_token":"synthetic-access","refresh_token":refresh,"expires_at":1,"user":["id":"synthetic-child","email":"child@example.invalid"]]
    }
    func testEmptyRefreshPausesRequestsAndRetainsChildIdentity() async {
        let network = SessionTransportFixture([])
        let account = RewardsStore(inMemory:true,initialSession:saved(" "),transport:{ try await network.send($0) })
        account.kind = "kids"
        XCTAssertTrue(account.needsReconnect)
        do { _ = try await account.request("/rest/v1/test");XCTFail("Expired credentials accepted") } catch { XCTAssertTrue(error.localizedDescription.contains("Reconnect")) }
        let calls = await network.calls;XCTAssertEqual(calls,0)
        XCTAssertEqual(account.kind,"kids");XCTAssertEqual(account.userID,"synthetic-child")
    }
    func testTerminalRefreshStopsRepeatingAndSameAccountRecoveryWorks() async throws {
        let network = SessionTransportFixture([400])
        let account = RewardsStore(inMemory:true,initialSession:saved(),transport:{ try await network.send($0) })
        account.kind = "kids"
        for _ in 0..<2 { do { _ = try await account.request("/rest/v1/test");XCTFail("Expected recovery") } catch {} }
        let calls = await network.calls;XCTAssertEqual(calls,1);XCTAssertTrue(account.needsReconnect)
        var replacement = saved("synthetic-password-session");replacement["expires_at"] = 4102444800
        try account.accept(replacement,expectedUserID:"synthetic-child")
        XCTAssertFalse(account.needsReconnect);XCTAssertEqual(account.kind,"kids")
        _ = try await account.request("/rest/v1/test")
    }
    func testTransientFailureRetainsRefreshAndRetries() async throws {
        let network = SessionTransportFixture([503])
        let account = RewardsStore(inMemory:true,initialSession:saved(),transport:{ try await network.send($0) })
        do { _ = try await account.request("/rest/v1/test");XCTFail("Expected outage") } catch {}
        XCTAssertFalse(account.needsReconnect)
        _ = try await account.request("/rest/v1/test")
        let calls = await network.calls;XCTAssertEqual(calls,3)
    }
    func testIncompleteOrDifferentAccountCannotReplaceSavedIdentity() throws {
        let account = RewardsStore(inMemory:true,initialSession:saved())
        account.kind = "kids"
        var incomplete = saved();incomplete["refresh_token"] = ""
        XCTAssertThrowsError(try account.accept(incomplete))
        var other = saved();other["user"] = ["id":"another-user"]
        XCTAssertThrowsError(try account.accept(other,expectedUserID:"synthetic-child"))
        XCTAssertEqual(account.userID,"synthetic-child");XCTAssertEqual(account.kind,"kids")
    }
}

@MainActor final class ConfirmedFeatureTests: XCTestCase {
 func testCrossPlatformEncryptedBackupVectorAndTamper() throws {
 let password = "Synthetic passphrase 2026!"
 let envelope = Data("{\"format\":\"OneStepEncrypted\",\"version\":1,\"kdf\":\"PBKDF2-HMAC-SHA256\",\"iterations\":600000,\"salt\":\"AAECAwQFBgcICQoLDA0ODw==\",\"nonce\":\"AAECAwQFBgcICQoL\",\"data\":\"JOkjaFtPpF2HiDNHRFSzzEe44lbqSj95ky3Ev4g7spUKxAPpkT074lEkCDr9DDmFJoym1JMgdcdHYPAAzQF4iEOUmbAAIz1k8if7S9dNxzVgjyjschDJxKsORFW1Wv5cP+FOWK43yEcpvO8d9MfxaAv0FlBZlMjXTIXSwOpF95SApp8G\"}".utf8)
 let clear = try BackupCrypto.open(envelope,password:password)
 XCTAssertEqual(String(data:clear,encoding:.utf8),"{\"format\":\"OneStep\",\"formatVersion\":1,\"exportedAt\":0,\"state\":{\"schemaVersion\":1,\"tasks\":[],\"routines\":[],\"days\":[]}}")
 _ = try TransferDocument.decode(clear)
 XCTAssertThrowsError(try BackupCrypto.open(envelope,password:"Wrong synthetic passphrase"))
 let sealed = try BackupCrypto.seal(clear,password:password)
 XCTAssertEqual(try BackupCrypto.open(sealed,password:password),clear)
 }
 func testRecurrenceFieldsSurviveStoreAndEncryptedTransfer() throws {
 let store = try PlannerStore(inMemory:true)
 XCTAssertTrue(store.saveTask(id:nil,title:"Monthly check",notes:"",dueAt:Date(),reminder:false,repeatRule:"monthly",repeatEvery:2,repeatWeekdays:[1,3],repeatMonthDay:31))
 let bytes = try BackupCrypto.seal(store.exportData(),password:"Synthetic passphrase 2026!")
 let restored = try TransferDocument.decode(BackupCrypto.open(bytes,password:"Synthetic passphrase 2026!"))
 XCTAssertEqual(restored.state.tasks[0].repeatMonthDay,31)
 XCTAssertEqual(restored.state.tasks[0].repeatEvery,2)
 }
 func testCapturePlannerCalendarAndBetaMore() async throws {
 let store = try PlannerStore(inMemory:true)
 XCTAssertTrue(store.saveTask(id:nil,title:"Read one page",notes:"One small step",dueAt:Date(),reminder:false,rewardPoints:10))
 for (name,view) in [("Calendar",AnyView(NavigationStack { PlannerCalendarView(edit:{ _ in }) })),("More",AnyView(RootView()))] {
 store.selectedTab = 4
 let host = UIHostingController(rootView:view.environment(store).environment(\.colorScheme,.dark))
 let window = UIWindow(frame:CGRect(x:0,y:0,width:390,height:844));window.rootViewController = host;window.makeKeyAndVisible()
 try await Task.sleep(nanoseconds:400_000_000)
 host.view.frame = window.bounds;host.view.layoutIfNeeded()
 let renderer = UIGraphicsImageRenderer(size:window.bounds.size)
 let image = renderer.image { _ in host.view.drawHierarchy(in:window.bounds,afterScreenUpdates:true) }
 let attachment = XCTAttachment(image:image);attachment.name = "OneStep-Beta-"+name;attachment.lifetime = .keepAlways;add(attachment)
 XCTAssertEqual(image.size.width,390);window.isHidden = true
 }
 }
}
