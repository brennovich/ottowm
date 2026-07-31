import XCTest

final class OperationCacheTests: XCTestCase {
    private var readCount = 0
    private var value: Int? = 100

    private lazy var cache = OperationCache { [weak self] () -> Int? in
        guard let self else { return nil }
        self.readCount += 1
        return self.value
    }

    func testReadsOnEveryLookupOutsideAnOperation() {
        XCTAssertEqual(cache.value(), 100)
        XCTAssertEqual(cache.value(), 100)

        XCTAssertEqual(readCount, 2)
    }

    func testReadsOnceWithinAnOperation() {
        cache.duringOperation {
            XCTAssertEqual(cache.value(), 100)
            value = 200
            XCTAssertEqual(cache.value(), 100)
        }

        XCTAssertEqual(readCount, 1)
    }

    func testReadIsDroppedWhenTheOperationEnds() {
        cache.duringOperation { _ = cache.value() }
        value = 200
        cache.duringOperation { XCTAssertEqual(cache.value(), 200) }

        XCTAssertEqual(readCount, 2)
    }

    func testNestedOperationsShareTheOuterRead() {
        cache.duringOperation {
            _ = cache.value()
            cache.duringOperation { _ = cache.value() }
            value = 200
            XCTAssertEqual(cache.value(), 100)
        }

        XCTAssertEqual(readCount, 1)
    }

    func testAbsentValueIsCachedToo() {
        value = nil

        cache.duringOperation {
            XCTAssertNil(cache.value())
            XCTAssertNil(cache.value())
        }

        XCTAssertEqual(readCount, 1)
    }
}
