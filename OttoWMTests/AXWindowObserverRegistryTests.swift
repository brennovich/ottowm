import ApplicationServices
import CoreGraphics
import XCTest

final class AXWindowObserverRegistryTests: XCTestCase {
    private let elementA = AXUIElementCreateApplication(901)
    private let elementB = AXUIElementCreateApplication(902)
    private let elementC = AXUIElementCreateApplication(903)

    func testRemoveWindowReturnsRegisteredId() {
        var registry = AXWindowObserver.Registry()
        registry.register(elementA, pid: 1, id: 100)

        XCTAssertEqual(registry.removeWindow(for: elementA), 100)
    }

    func testRemoveWindowForUnknownElementReturnsNil() {
        var registry = AXWindowObserver.Registry()

        XCTAssertNil(registry.removeWindow(for: elementA))
    }

    func testRemoveWindowTwiceReturnsNilTheSecondTime() {
        var registry = AXWindowObserver.Registry()
        registry.register(elementA, pid: 1, id: 100)

        XCTAssertEqual(registry.removeWindow(for: elementA), 100)
        XCTAssertNil(registry.removeWindow(for: elementA))
    }

    func testMatchesElementsByValueNotByInstance() {
        var registry = AXWindowObserver.Registry()
        registry.register(AXUIElementCreateApplication(904), pid: 1, id: 100)

        XCTAssertEqual(registry.removeWindow(for: AXUIElementCreateApplication(904)), 100)
    }

    func testRegisterSameElementTwiceKeepsLastId() {
        var registry = AXWindowObserver.Registry()
        registry.register(elementA, pid: 1, id: 100)
        registry.register(elementA, pid: 1, id: 200)

        XCTAssertEqual(registry.removeWindow(for: elementA), 200)
    }

    func testEvictRemovesOnlyThatPidsElements() {
        var registry = AXWindowObserver.Registry()
        registry.register(elementA, pid: 1, id: 100)
        registry.register(elementB, pid: 1, id: 200)
        registry.register(elementC, pid: 2, id: 300)

        registry.evict(pid: 1)

        XCTAssertNil(registry.removeWindow(for: elementA))
        XCTAssertNil(registry.removeWindow(for: elementB))
        XCTAssertEqual(registry.removeWindow(for: elementC), 300)
    }

    func testUnregistered() {
        let cases: [(name: String, registered: [AXUIElement], elements: [AXUIElement], expected: [AXUIElement])] = [
            ("empty registry keeps all", [], [elementA, elementB], [elementA, elementB]),
            ("partially registered filters known", [elementA], [elementA, elementB, elementC], [elementB, elementC]),
            ("fully registered filters all", [elementA, elementB], [elementA, elementB], []),
            ("preserves input order", [elementB], [elementC, elementB, elementA], [elementC, elementA]),
        ]

        for testCase in cases {
            var registry = AXWindowObserver.Registry()
            for (index, element) in testCase.registered.enumerated() {
                registry.register(element, pid: 1, id: CGWindowID(index + 100))
            }

            XCTAssertEqual(registry.unregistered(of: testCase.elements), testCase.expected, testCase.name)
        }
    }

    func testElementForIdReturnsRegisteredElementAndPid() {
        var registry = AXWindowObserver.Registry()
        registry.register(elementA, pid: 1, id: 100)
        registry.register(elementB, pid: 2, id: 200)

        let found = registry.element(for: 200)

        XCTAssertEqual(found?.element, elementB)
        XCTAssertEqual(found?.pid, 2)
    }

    func testElementForUnknownIdReturnsNil() {
        var registry = AXWindowObserver.Registry()
        registry.register(elementA, pid: 1, id: 100)

        XCTAssertNil(registry.element(for: 999))
    }

    func testElementForIdAfterReregisterTracksTheLastId() {
        var registry = AXWindowObserver.Registry()
        registry.register(elementA, pid: 1, id: 100)
        registry.register(elementA, pid: 1, id: 200)

        XCTAssertNil(registry.element(for: 100))
        XCTAssertEqual(registry.element(for: 200)?.element, elementA)
    }

    func testElementForIdAfterRemoveReturnsNil() {
        var registry = AXWindowObserver.Registry()
        registry.register(elementA, pid: 1, id: 100)
        _ = registry.removeWindow(for: elementA)

        XCTAssertNil(registry.element(for: 100))
    }

    func testElementForIdAfterEvictReturnsNil() {
        var registry = AXWindowObserver.Registry()
        registry.register(elementA, pid: 1, id: 100)
        registry.evict(pid: 1)

        XCTAssertNil(registry.element(for: 100))
    }

    func testRemovedElementReappearsInUnregistered() {
        var registry = AXWindowObserver.Registry()
        registry.register(elementA, pid: 1, id: 100)
        _ = registry.removeWindow(for: elementA)

        XCTAssertEqual(registry.unregistered(of: [elementA]), [elementA])
    }
}
