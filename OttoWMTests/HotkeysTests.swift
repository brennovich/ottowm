import CoreGraphics
import XCTest

final class HotkeysTests: XCTestCase {
    private var deferred: [() -> Void] = []
    private var received: [Action] = []
    private var matched: [(keyCode: Int64, flags: CGEventFlags)] = []

    private func makeHotkeys() -> Hotkeys {
        Hotkeys(
            keyCodeMatcher: { keyCode, flags in
                self.matched.append((keyCode, flags))
                switch keyCode {
                case 18: return .switchToWorkspace(1)
                case 20: return .moveWindowToWorkspace(3)
                default: return nil
                }
            },
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
        let hotkeys = makeHotkeys()

        XCTAssertNil(hotkeys.handle(type: .keyDown, event: try keyDown(18, .leftOption)))
        XCTAssertNil(hotkeys.handle(type: .keyDown, event: try keyDown(20, [.leftOption, .leftShift])))
        XCTAssertEqual(received, [])

        deferred.forEach { $0() }

        XCTAssertEqual(received, [.switchToWorkspace(1), .moveWindowToWorkspace(3)])
    }

    func testMatcherReceivesTheKeystrokesKeyCodeAndFlags() throws {
        let hotkeys = makeHotkeys()

        _ = hotkeys.handle(type: .keyDown, event: try keyDown(18, .leftOption))

        XCTAssertEqual(matched.count, 1)
        XCTAssertEqual(matched[0].keyCode, 18)
        XCTAssertTrue(matched[0].flags.contains(.leftOption))
    }

    func testUnmatchedKeyPassesThroughWithoutDeferringAnything() throws {
        let hotkeys = makeHotkeys()
        let event = try keyDown(0, .leftOption)

        XCTAssertTrue(hotkeys.handle(type: .keyDown, event: event)?.takeUnretainedValue() === event)
        XCTAssertEqual(deferred.count, 0)
    }

    func testDisabledTapPassesABoundKeystrokeThrough() throws {
        let hotkeys = makeHotkeys()

        for type: CGEventType in [.tapDisabledByTimeout, .tapDisabledByUserInput] {
            let event = try keyDown(18, .leftOption)
            XCTAssertTrue(hotkeys.handle(type: type, event: event)?.takeUnretainedValue() === event)
        }

        XCTAssertEqual(deferred.count, 0)
    }

    func testDeferredActionIsDroppedOnceTheTapIsReleased() throws {
        var hotkeys: Hotkeys? = makeHotkeys()

        _ = hotkeys?.handle(type: .keyDown, event: try keyDown(18, .leftOption))
        hotkeys = nil
        deferred.forEach { $0() }

        XCTAssertEqual(received, [])
    }
}
