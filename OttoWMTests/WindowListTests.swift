import CoreGraphics
import XCTest

final class WindowListTests: XCTestCase {
    func testOnScreenWindowIds() {
        let key = kCGWindowNumber as String
        let cases: [(name: String, infoList: [[String: Any]], expected: Set<CGWindowID>)] = [
            ("empty list", [], []),
            ("entries with window numbers", [[key: NSNumber(value: 100)], [key: NSNumber(value: 200)]], [100, 200]),
            ("entry missing the key", [[key: NSNumber(value: 100)], ["other": NSNumber(value: 200)]], [100]),
            ("non-number value", [[key: "not a number"], [key: NSNumber(value: 300)]], [300]),
            ("duplicate ids", [[key: NSNumber(value: 100)], [key: NSNumber(value: 100)]], [100]),
        ]

        for testCase in cases {
            XCTAssertEqual(onScreenWindowIds(from: testCase.infoList), testCase.expected, testCase.name)
        }
    }
}

final class OnScreenWindowsTests: XCTestCase {
    private var snapshotCount = 0
    private var ids: Set<CGWindowID> = [100]

    private lazy var onScreenWindows = OnScreenWindows { [weak self] in
        guard let self else { return [] }
        self.snapshotCount += 1
        return self.ids
    }

    func testSnapshotsOnEveryReadOutsideAnOperation() {
        XCTAssertEqual(onScreenWindows.ids(), [100])
        XCTAssertEqual(onScreenWindows.ids(), [100])

        XCTAssertEqual(snapshotCount, 2)
    }

    func testSnapshotsOnceWithinAnOperation() {
        onScreenWindows.duringOperation {
            XCTAssertEqual(onScreenWindows.ids(), [100])
            ids = [200]
            XCTAssertEqual(onScreenWindows.ids(), [100])
        }

        XCTAssertEqual(snapshotCount, 1)
    }

    func testSnapshotIsDroppedWhenTheOperationEnds() {
        onScreenWindows.duringOperation { _ = onScreenWindows.ids() }
        ids = [200]
        onScreenWindows.duringOperation { XCTAssertEqual(onScreenWindows.ids(), [200]) }

        XCTAssertEqual(snapshotCount, 2)
    }

    func testNestedOperationsShareTheOuterSnapshot() {
        onScreenWindows.duringOperation {
            _ = onScreenWindows.ids()
            onScreenWindows.duringOperation { _ = onScreenWindows.ids() }
            ids = [200]
            XCTAssertEqual(onScreenWindows.ids(), [100])
        }

        XCTAssertEqual(snapshotCount, 1)
    }
}
