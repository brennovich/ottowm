import CoreGraphics
import XCTest

final class ObservedWindowRegistryTests: XCTestCase {
    func testRemoveWindowReturnsRegisteredId() {
        var registry = ObservedWindowRegistry<String>()
        registry.register("a", pid: 1, id: 100)

        XCTAssertEqual(registry.removeWindow(for: "a"), 100)
    }

    func testRemoveWindowForUnknownElementReturnsNil() {
        var registry = ObservedWindowRegistry<String>()

        XCTAssertNil(registry.removeWindow(for: "a"))
    }

    func testRemoveWindowTwiceReturnsNilTheSecondTime() {
        var registry = ObservedWindowRegistry<String>()
        registry.register("a", pid: 1, id: 100)

        XCTAssertEqual(registry.removeWindow(for: "a"), 100)
        XCTAssertNil(registry.removeWindow(for: "a"))
    }

    func testRegisterSameElementTwiceKeepsLastId() {
        var registry = ObservedWindowRegistry<String>()
        registry.register("a", pid: 1, id: 100)
        registry.register("a", pid: 1, id: 200)

        XCTAssertEqual(registry.removeWindow(for: "a"), 200)
    }

    func testEvictRemovesOnlyThatPidsElements() {
        var registry = ObservedWindowRegistry<String>()
        registry.register("a", pid: 1, id: 100)
        registry.register("b", pid: 1, id: 200)
        registry.register("c", pid: 2, id: 300)

        registry.evict(pid: 1)

        XCTAssertNil(registry.removeWindow(for: "a"))
        XCTAssertNil(registry.removeWindow(for: "b"))
        XCTAssertEqual(registry.removeWindow(for: "c"), 300)
    }

    func testUnregistered() {
        let cases: [(name: String, registered: [String], elements: [String], expected: [String])] = [
            ("empty registry keeps all", [], ["a", "b"], ["a", "b"]),
            ("partially registered filters known", ["a"], ["a", "b", "c"], ["b", "c"]),
            ("fully registered filters all", ["a", "b"], ["a", "b"], []),
            ("preserves input order", ["b"], ["c", "b", "a"], ["c", "a"]),
        ]

        for testCase in cases {
            var registry = ObservedWindowRegistry<String>()
            for (index, element) in testCase.registered.enumerated() {
                registry.register(element, pid: 1, id: CGWindowID(index + 100))
            }

            XCTAssertEqual(registry.unregistered(of: testCase.elements), testCase.expected, testCase.name)
        }
    }

    func testElementForIdReturnsRegisteredElementAndPid() {
        var registry = ObservedWindowRegistry<String>()
        registry.register("a", pid: 1, id: 100)
        registry.register("b", pid: 2, id: 200)

        let found = registry.element(for: 200)

        XCTAssertEqual(found?.element, "b")
        XCTAssertEqual(found?.pid, 2)
    }

    func testElementForUnknownIdReturnsNil() {
        var registry = ObservedWindowRegistry<String>()
        registry.register("a", pid: 1, id: 100)

        XCTAssertNil(registry.element(for: 999))
    }

    func testElementForIdAfterReregisterTracksTheLastId() {
        var registry = ObservedWindowRegistry<String>()
        registry.register("a", pid: 1, id: 100)
        registry.register("a", pid: 1, id: 200)

        XCTAssertNil(registry.element(for: 100))
        XCTAssertEqual(registry.element(for: 200)?.element, "a")
    }

    func testElementForIdAfterRemoveReturnsNil() {
        var registry = ObservedWindowRegistry<String>()
        registry.register("a", pid: 1, id: 100)
        _ = registry.removeWindow(for: "a")

        XCTAssertNil(registry.element(for: 100))
    }

    func testElementForIdAfterEvictReturnsNil() {
        var registry = ObservedWindowRegistry<String>()
        registry.register("a", pid: 1, id: 100)
        registry.evict(pid: 1)

        XCTAssertNil(registry.element(for: 100))
    }

    func testRemovedElementReappearsInUnregistered() {
        var registry = ObservedWindowRegistry<String>()
        registry.register("a", pid: 1, id: 100)
        _ = registry.removeWindow(for: "a")

        XCTAssertEqual(registry.unregistered(of: ["a"]), ["a"])
    }
}
