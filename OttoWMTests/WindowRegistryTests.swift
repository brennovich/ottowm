import AppKit
import ApplicationServices
import CoreGraphics
import XCTest

final class WindowRegistryTests: XCTestCase {
    private let elementA = AXUIElementCreateApplication(901)
    private let elementB = AXUIElementCreateApplication(902)
    private let elementC = AXUIElementCreateApplication(903)
    private let app = NSRunningApplication.current
    private lazy var pid = app.processIdentifier
    private lazy var element = AXUIElementCreateApplication(pid)

    func testRemoveWindowForUnknownElementReturnsNil() {
        let registry = WindowRegistry()

        XCTAssertNil(registry.removeWindow(for: elementA))
    }

    func testRemoveWindowTwiceReturnsNilTheSecondTime() {
        let registry = WindowRegistry()
        registry.register(elementA, pid: 1, id: 100)

        XCTAssertEqual(registry.removeWindow(for: elementA), 100)
        XCTAssertNil(registry.removeWindow(for: elementA))
    }

    func testMatchesElementsByValueNotByInstance() {
        let registry = WindowRegistry()
        registry.register(AXUIElementCreateApplication(904), pid: 1, id: 100)

        XCTAssertEqual(registry.removeWindow(for: AXUIElementCreateApplication(904)), 100)
    }

    func testKnownWindowsPairsEveryRegisteredElementWithItsId() {
        let registry = WindowRegistry()
        registry.register(elementA, pid: 1, id: 100)
        registry.register(elementB, pid: 2, id: 200)
        _ = registry.removeWindow(for: elementA)

        XCTAssertEqual(registry.knownWindows.map(\.id), [200])
        XCTAssertEqual(registry.knownWindows.map(\.element), [elementB])
    }

    func testEvictRemovesOnlyThatPidsElements() {
        let registry = WindowRegistry()
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
            let registry = WindowRegistry()
            for (index, element) in testCase.registered.enumerated() {
                registry.register(element, pid: 1, id: CGWindowID(index + 100))
            }

            XCTAssertEqual(registry.unregistered(of: testCase.elements), testCase.expected, testCase.name)
        }
    }

    func testElementForIdReturnsRegisteredElementAndPid() {
        let registry = WindowRegistry()
        registry.register(elementA, pid: 1, id: 100)
        registry.register(elementB, pid: 2, id: 200)

        let found = registry.element(for: 200)

        XCTAssertEqual(found?.element, elementB)
        XCTAssertEqual(found?.pid, 2)
    }

    func testElementForUnknownIdReturnsNil() {
        let registry = WindowRegistry()
        registry.register(elementA, pid: 1, id: 100)

        XCTAssertNil(registry.element(for: 999))
    }

    func testReregisteringAnElementTracksTheLastId() {
        let registry = WindowRegistry()
        registry.register(elementA, pid: 1, id: 100)
        registry.register(elementA, pid: 1, id: 200)

        XCTAssertNil(registry.element(for: 100))
        XCTAssertEqual(registry.element(for: 200)?.element, elementA)
        XCTAssertEqual(registry.removeWindow(for: elementA), 200)
    }

    func testElementForIdAfterRemoveReturnsNil() {
        let registry = WindowRegistry()
        registry.register(elementA, pid: 1, id: 100)
        _ = registry.removeWindow(for: elementA)

        XCTAssertNil(registry.element(for: 100))
    }

    func testElementForIdAfterEvictReturnsNil() {
        let registry = WindowRegistry()
        registry.register(elementA, pid: 1, id: 100)
        registry.evict(pid: 1)

        XCTAssertNil(registry.element(for: 100))
    }

    func testRemovedElementReappearsInUnregistered() {
        let registry = WindowRegistry()
        registry.register(elementA, pid: 1, id: 100)
        _ = registry.removeWindow(for: elementA)

        XCTAssertEqual(registry.unregistered(of: [elementA]), [elementA])
    }

    func testWindowByUnknownIdReturnsNil() {
        let registry = WindowRegistry()

        XCTAssertNil(registry.window(for: 100))
    }

    func testWindowByIdReturnsRegisteredWindow() {
        let registry = WindowRegistry()
        registry.add(app)
        registry.register(element, pid: pid, id: 100)

        let window = registry.window(for: 100)

        XCTAssertEqual(window?.id, 100)
        XCTAssertEqual(window?.element, element)
        XCTAssertEqual(window?.application.processIdentifier, pid)
    }

    func testWindowByIdWithoutApplicationReturnsNil() {
        let registry = WindowRegistry()
        registry.register(element, pid: pid, id: 100)

        XCTAssertNil(registry.window(for: 100))
    }

    func testWindowByIdAfterEvictReturnsNil() {
        let registry = WindowRegistry()
        registry.add(app)
        registry.register(element, pid: pid, id: 100)
        registry.evict(pid: pid)

        XCTAssertNil(registry.window(for: 100))
    }
}
