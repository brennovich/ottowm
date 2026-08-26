import AppKit
import ApplicationServices
import CoreGraphics
import XCTest

/// The AXUIElement <-> CGWindowID map behind KnownWindows, exercised through the
/// observing API that fills it.
final class KnownWindowsTests: XCTestCase {
    private let harness = KnownWindowsHarness()
    private let app = StubRunningApplication(pid: 901)
    private lazy var known = harness.knownWindows

    private func observe(_ app: NSRunningApplication) {
        _ = known.observe(app, notify: { _, _ in })
    }

    func testWindowForIdReturnsTheRegisteredWindow() {
        let element = harness.addWindow(pid: 901, id: 100)
        observe(app)

        let window = known.window(for: 100)

        XCTAssertEqual(window?.id, 100)
        XCTAssertEqual(window?.element, element)
        XCTAssertEqual(window?.application.processIdentifier, 901)
    }

    func testWindowForUnknownIdReturnsNil() {
        observe(app)

        XCTAssertNil(known.window(for: 100))
    }

    func testRemoveWindowReturnsTheIdAndForgetsTheWindow() {
        let element = harness.addWindow(pid: 901, id: 100)
        observe(app)

        XCTAssertEqual(known.removeWindow(for: element), 100)
        XCTAssertNil(known.window(for: 100))
        XCTAssertNil(known.removeWindow(for: element))
    }

    func testRemoveWindowForUnknownElementReturnsNil() {
        observe(app)

        XCTAssertNil(known.removeWindow(for: harness.makeElement(id: 42)))
    }

    func testMatchesElementsByValueNotByInstance() {
        let element = AXUIElementCreateApplication(904)
        harness.windowIds[element] = 100
        harness.elements[901] = [element]
        observe(app)

        XCTAssertEqual(known.removeWindow(for: AXUIElementCreateApplication(904)), 100)
    }

    func testStopObservingForgetsOnlyThatApplicationsWindows() {
        let other = StubRunningApplication(pid: 902)
        harness.addWindow(pid: 901, id: 100)
        harness.addWindow(pid: 902, id: 200)
        observe(app)
        observe(other)

        known.stopObserving(app)

        XCTAssertNil(known.window(for: 100))
        XCTAssertEqual(known.window(for: 200)?.id, 200)
    }

    func testRemovedWindowIsFoundAgainByRescan() {
        let element = harness.addWindow(pid: 901, id: 100)
        observe(app)
        _ = known.removeWindow(for: element)

        XCTAssertEqual(known.rescan(app).map(\.id), [100])
        XCTAssertEqual(known.window(for: 100)?.element, element)
    }
}
