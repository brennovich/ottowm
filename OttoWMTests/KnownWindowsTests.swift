import AppKit
import ApplicationServices
import CoreGraphics
import XCTest

final class KnownWindowsTests: XCTestCase {
    private let elementA = AXUIElementCreateApplication(901)
    private let elementB = AXUIElementCreateApplication(902)
    private let elementC = AXUIElementCreateApplication(903)
    private let app = NSRunningApplication.current
    private lazy var pid = app.processIdentifier
    private lazy var element = AXUIElementCreateApplication(pid)

    func testRemoveWindowForUnknownElementReturnsNil() {
        let known = KnownWindows()

        XCTAssertNil(known.removeWindow(for: elementA))
    }

    func testRemoveWindowTwiceReturnsNilTheSecondTime() {
        let known = KnownWindows()
        known.register(elementA, pid: 1, id: 100)

        XCTAssertEqual(known.removeWindow(for: elementA), 100)
        XCTAssertNil(known.removeWindow(for: elementA))
    }

    func testMatchesElementsByValueNotByInstance() {
        let known = KnownWindows()
        known.register(AXUIElementCreateApplication(904), pid: 1, id: 100)

        XCTAssertEqual(known.removeWindow(for: AXUIElementCreateApplication(904)), 100)
    }

    func testRegisteredPairsEveryRegisteredElementWithItsId() {
        let known = KnownWindows()
        known.register(elementA, pid: 1, id: 100)
        known.register(elementB, pid: 2, id: 200)
        _ = known.removeWindow(for: elementA)

        XCTAssertEqual(known.registered.map(\.id), [200])
        XCTAssertEqual(known.registered.map(\.element), [elementB])
    }

    func testEvictRemovesOnlyThatPidsElements() {
        let known = KnownWindows()
        known.register(elementA, pid: 1, id: 100)
        known.register(elementB, pid: 1, id: 200)
        known.register(elementC, pid: 2, id: 300)

        known.evict(pid: 1)

        XCTAssertNil(known.removeWindow(for: elementA))
        XCTAssertNil(known.removeWindow(for: elementB))
        XCTAssertEqual(known.removeWindow(for: elementC), 300)
    }

    func testUnregistered() {
        let cases: [(name: String, registered: [AXUIElement], elements: [AXUIElement], expected: [AXUIElement])] = [
            ("empty known keeps all", [], [elementA, elementB], [elementA, elementB]),
            ("partially registered filters known", [elementA], [elementA, elementB, elementC], [elementB, elementC]),
            ("fully registered filters all", [elementA, elementB], [elementA, elementB], []),
            ("preserves input order", [elementB], [elementC, elementB, elementA], [elementC, elementA]),
        ]

        for testCase in cases {
            let known = KnownWindows()
            for (index, element) in testCase.registered.enumerated() {
                known.register(element, pid: 1, id: CGWindowID(index + 100))
            }

            XCTAssertEqual(known.unregistered(of: testCase.elements), testCase.expected, testCase.name)
        }
    }

    func testElementForIdReturnsRegisteredElementAndPid() {
        let known = KnownWindows()
        known.register(elementA, pid: 1, id: 100)
        known.register(elementB, pid: 2, id: 200)

        let found = known.element(for: 200)

        XCTAssertEqual(found?.element, elementB)
        XCTAssertEqual(found?.pid, 2)
    }

    func testElementForUnknownIdReturnsNil() {
        let known = KnownWindows()
        known.register(elementA, pid: 1, id: 100)

        XCTAssertNil(known.element(for: 999))
    }

    func testReregisteringAnElementTracksTheLastId() {
        let known = KnownWindows()
        known.register(elementA, pid: 1, id: 100)
        known.register(elementA, pid: 1, id: 200)

        XCTAssertNil(known.element(for: 100))
        XCTAssertEqual(known.element(for: 200)?.element, elementA)
        XCTAssertEqual(known.removeWindow(for: elementA), 200)
    }

    func testElementForIdAfterRemoveReturnsNil() {
        let known = KnownWindows()
        known.register(elementA, pid: 1, id: 100)
        _ = known.removeWindow(for: elementA)

        XCTAssertNil(known.element(for: 100))
    }

    func testElementForIdAfterEvictReturnsNil() {
        let known = KnownWindows()
        known.register(elementA, pid: 1, id: 100)
        known.evict(pid: 1)

        XCTAssertNil(known.element(for: 100))
    }

    func testRemovedElementReappearsInUnregistered() {
        let known = KnownWindows()
        known.register(elementA, pid: 1, id: 100)
        _ = known.removeWindow(for: elementA)

        XCTAssertEqual(known.unregistered(of: [elementA]), [elementA])
    }

    func testWindowByUnknownIdReturnsNil() {
        let known = KnownWindows()

        XCTAssertNil(known.window(for: 100))
    }

    func testWindowByIdReturnsRegisteredWindow() {
        let known = KnownWindows()
        known.add(app)
        known.register(element, pid: pid, id: 100)

        let window = known.window(for: 100)

        XCTAssertEqual(window?.id, 100)
        XCTAssertEqual(window?.element, element)
        XCTAssertEqual(window?.application.processIdentifier, pid)
    }

    func testWindowByIdWithoutApplicationReturnsNil() {
        let known = KnownWindows()
        known.register(element, pid: pid, id: 100)

        XCTAssertNil(known.window(for: 100))
    }

    func testWindowByIdAfterEvictReturnsNil() {
        let known = KnownWindows()
        known.add(app)
        known.register(element, pid: pid, id: 100)
        known.evict(pid: pid)

        XCTAssertNil(known.window(for: 100))
    }
}
