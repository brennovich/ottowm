import CoreGraphics
import XCTest

final class FocusedWindowTests: XCTestCase {
    private var readCount = 0
    private var snapshot: WindowSnapshot? = makeSnapshot(100)

    private lazy var focusedWindow = FocusedWindow { [weak self] in
        guard let self else { return nil }
        self.readCount += 1
        return self.snapshot
    }

    func testReadsOnEveryLookupOutsideAnOperation() {
        XCTAssertEqual(focusedWindow.snapshot(), makeSnapshot(100))
        XCTAssertEqual(focusedWindow.snapshot(), makeSnapshot(100))

        XCTAssertEqual(readCount, 2)
    }

    func testReadsOnceWithinAnOperation() {
        focusedWindow.duringOperation {
            XCTAssertEqual(focusedWindow.snapshot(), makeSnapshot(100))
            snapshot = makeSnapshot(200)
            XCTAssertEqual(focusedWindow.snapshot(), makeSnapshot(100))
        }

        XCTAssertEqual(readCount, 1)
    }

    func testReadIsDroppedWhenTheOperationEnds() {
        focusedWindow.duringOperation { _ = focusedWindow.snapshot() }
        snapshot = makeSnapshot(200)
        focusedWindow.duringOperation { XCTAssertEqual(focusedWindow.snapshot(), makeSnapshot(200)) }

        XCTAssertEqual(readCount, 2)
    }

    func testNestedOperationsShareTheOuterRead() {
        focusedWindow.duringOperation {
            _ = focusedWindow.snapshot()
            focusedWindow.duringOperation { _ = focusedWindow.snapshot() }
            snapshot = makeSnapshot(200)
            XCTAssertEqual(focusedWindow.snapshot(), makeSnapshot(100))
        }

        XCTAssertEqual(readCount, 1)
    }

    func testAbsenceOfAFocusedWindowIsCachedToo() {
        snapshot = nil

        focusedWindow.duringOperation {
            XCTAssertNil(focusedWindow.snapshot())
            XCTAssertNil(focusedWindow.snapshot())
        }

        XCTAssertEqual(readCount, 1)
    }
}
