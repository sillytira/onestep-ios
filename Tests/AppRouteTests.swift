import XCTest
@testable import OneStepCore

final class AppRouteTests: XCTestCase {
    func testAllSupportedLinksSelectTheirDestination() throws {
        for (host, tab) in [("now",0),("add",1),("routines",2),("bank",3),("space",4),("timer",0)] {
            let route = try XCTUnwrap(AppRoute(url:URL(string:"onestep://\(host)")!))
            XCTAssertEqual(route.tab,tab)
        }
    }
    func testUnrelatedAndUnknownLinksCannotChangeNavigation() {
        XCTAssertNil(AppRoute(url:URL(string:"https://example.invalid/bank")!))
        XCTAssertNil(AppRoute(url:URL(string:"onestep://unknown")!))
    }
}
