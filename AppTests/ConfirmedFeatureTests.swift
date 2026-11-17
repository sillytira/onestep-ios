import XCTest
import SwiftUI
import UIKit
@testable import OneStep

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
