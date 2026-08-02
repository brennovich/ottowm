import CoreGraphics
import XCTest

final class HotkeyEventTapTests: XCTestCase {
    private var deferred: [() -> Void] = []
    private var received: [Action] = []

    private func makeTap() throws -> HotkeyEventTap {
        HotkeyEventTap(
            config: try makeConfig([
                "lalt-1": .switchToWorkspace(1),
                "lalt-shift-3": .moveWindowToWorkspace(3),
            ]),
            dispatch: { self.deferred.append($0) },
            handler: { self.received.append($0) }
        )
    }

    private func keyDown(_ keyCode: CGKeyCode, _ flags: CGEventFlags) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
        event.flags = flags
        return event
    }

    func testConsumedHotkeysRunOffTheCallbackInOrder() throws {
        let tap = try makeTap()

        XCTAssertNil(tap.handle(type: .keyDown, event: try keyDown(18, .leftOption)))
        XCTAssertNil(tap.handle(type: .keyDown, event: try keyDown(20, [.leftOption, .leftShift])))
        XCTAssertEqual(received, [])

        deferred.forEach { $0() }

        XCTAssertEqual(received, [.switchToWorkspace(1), .moveWindowToWorkspace(3)])
    }

    func testUnmatchedKeyPassesThroughWithoutDeferringAnything() throws {
        let tap = try makeTap()
        let event = try keyDown(0, .leftOption)

        XCTAssertTrue(tap.handle(type: .keyDown, event: event)?.takeUnretainedValue() === event)
        XCTAssertEqual(deferred.count, 0)
    }

    func testDisabledTapPassesABoundKeystrokeThrough() throws {
        let tap = try makeTap()

        for type: CGEventType in [.tapDisabledByTimeout, .tapDisabledByUserInput] {
            let event = try keyDown(18, .leftOption)
            XCTAssertTrue(tap.handle(type: type, event: event)?.takeUnretainedValue() === event)
        }

        XCTAssertEqual(deferred.count, 0)
    }

    func testDeferredActionIsDroppedOnceTheTapIsReleased() throws {
        var tap: HotkeyEventTap? = try makeTap()

        _ = tap?.handle(type: .keyDown, event: try keyDown(18, .leftOption))
        tap = nil
        deferred.forEach { $0() }

        XCTAssertEqual(received, [])
    }
}
