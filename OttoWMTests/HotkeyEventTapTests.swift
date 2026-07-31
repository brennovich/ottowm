import CoreGraphics
import XCTest

final class HotkeyEventTapTests: XCTestCase {
    private let leftOption: CGEventFlags = [.maskAlternate, CGEventFlags(rawValue: 0x20)]

    private func keyDown(_ keyCode: CGKeyCode, _ flags: CGEventFlags) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
        event.flags = flags
        return event
    }

    func testConsumedHotkeyDefersTheActionOffTheCallback() throws {
        var deferred: [() -> Void] = []
        var received: [HotkeyAction] = []
        let tap = HotkeyEventTap(dispatch: { deferred.append($0) }) { received.append($0) }

        let result = tap.handle(type: .keyDown, event: try keyDown(18, leftOption))

        XCTAssertNil(result)
        XCTAssertEqual(received, [])
        XCTAssertEqual(deferred.count, 1)

        deferred.forEach { $0() }
        XCTAssertEqual(received, [.switchToVirtualSpace(1)])
    }

    func testConsumedHotkeysAreDeferredInOrder() throws {
        var deferred: [() -> Void] = []
        var received: [HotkeyAction] = []
        let tap = HotkeyEventTap(dispatch: { deferred.append($0) }) { received.append($0) }

        _ = tap.handle(type: .keyDown, event: try keyDown(19, leftOption))
        _ = tap.handle(type: .keyDown, event: try keyDown(20, leftOption.union(.maskShift)))
        deferred.forEach { $0() }

        XCTAssertEqual(received, [.switchToVirtualSpace(2), .moveWindowToVirtualSpace(3)])
    }

    func testUnmatchedKeyPassesThroughWithoutDeferringAnything() throws {
        var deferred: [() -> Void] = []
        let tap = HotkeyEventTap(dispatch: { deferred.append($0) }) { _ in }

        let event = try keyDown(0, leftOption)
        let result = tap.handle(type: .keyDown, event: event)

        XCTAssertTrue(result?.takeUnretainedValue() === event)
        XCTAssertEqual(deferred.count, 0)
    }

    func testDeferredActionIsDroppedOnceTheTapIsReleased() throws {
        var deferred: [() -> Void] = []
        var received: [HotkeyAction] = []
        var tap: HotkeyEventTap? = HotkeyEventTap(dispatch: { deferred.append($0) }) { received.append($0) }

        _ = tap?.handle(type: .keyDown, event: try keyDown(18, leftOption))
        tap = nil
        deferred.forEach { $0() }

        XCTAssertEqual(received, [])
    }
}
