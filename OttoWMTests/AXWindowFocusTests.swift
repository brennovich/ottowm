import AppKit
import ApplicationServices
import XCTest

final class AXWindowFocusTests: XCTestCase {
    private let window = NSWindow(
        contentRect: CGRect(x: 100, y: 100, width: 400, height: 300),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    private let sheet = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 200, height: 150),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )

    override func setUp() {
        super.setUp()
        NSApplication.shared.finishLaunching()
    }

    override func tearDown() {
        window.endSheet(sheet)
        window.close()
        super.tearDown()
    }

    func testTheFocusedWindowOfAnApplicationShowingASheetIsTheWindowItBelongsTo() {
        window.makeKeyAndOrderFront(nil)
        window.beginSheet(sheet)
        waitForFocusedWindow(CGWindowID(sheet.windowNumber))

        XCTAssertEqual(focusedElementId(), CGWindowID(sheet.windowNumber))
        XCTAssertEqual(AXWindow.focused(of: .current)?.id, CGWindowID(window.windowNumber))
    }

    private func waitForFocusedWindow(_ windowId: CGWindowID) {
        let deadline = Date().addingTimeInterval(2)
        while focusedElementId() != windowId, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func focusedElementId() -> CGWindowID? {
        let appElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        guard let element = appElement.elementValue(of: .focusedWindow) else { return nil }
        return AXWindow(element: element, application: .current).id
    }
}
