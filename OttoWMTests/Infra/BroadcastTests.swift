import XCTest

final class BroadcastTests: XCTestCase {
    private var broadcast = Broadcast<Int>()

    func testEverySubscriptionReceivesEachEventOnce() {
        var first: [Int] = []
        var second: [Int] = []
        broadcast.watch { first.append($0) }
        broadcast.watch { second.append($0) }

        broadcast.report(1)
        broadcast.report(2)

        XCTAssertEqual(first, [1, 2])
        XCTAssertEqual(second, [1, 2])
    }
}
