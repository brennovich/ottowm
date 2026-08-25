import AppKit

// Only the raw event flags tell the left Option key from the right one, and the bundled
// workspace bindings are all left Option, so the device dependent bits of
// Core/Config/KeyCombo.swift have to be set by hand. System Events cannot produce them.
// The bundled quit and restart bindings are hyper, which takes either side of every
// modifier, so the masks alone match them.
let leftOptionBit: UInt64 = 0x20
let leftShiftBit: UInt64 = 0x2

let keyCodesByWorkspace: [Int: CGKeyCode] = [1: 18, 2: 19, 3: 20, 4: 21, 5: 23]
let quitKeyCode: CGKeyCode = 12
let restartKeyCode: CGKeyCode = 15

// Built once rather than per post: the benchmark reads its clock before the hotkey goes
// out, so anything built inside post() is charged to the app as latency.
let eventSource: CGEventSource = {
    guard let source = CGEventSource(stateID: .hidSystemState) else { fail("cannot create an event source") }

    return source
}()

func post(_ keyCode: CGKeyCode, _ flags: CGEventFlags) {
    for keyDown in [true, false] {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: keyDown) else {
            fail("cannot create a key event")
        }
        event.flags = keyDown ? flags : []
        event.post(tap: .cgSessionEventTap)
    }
}

func keyCode(forWorkspace workspace: Int) -> CGKeyCode {
    guard let keyCode = keyCodesByWorkspace[workspace] else { fail("no key bound to workspace \(workspace)") }
    return keyCode
}

func switchToWorkspace(_ workspace: Int) {
    post(keyCode(forWorkspace: workspace), CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | leftOptionBit))
}

func moveWindowToWorkspace(_ workspace: Int) {
    post(
        keyCode(forWorkspace: workspace),
        CGEventFlags(
            rawValue: CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue
                | leftOptionBit | leftShiftBit
        )
    )
}

func quit() {
    post(quitKeyCode, [.maskCommand, .maskControl, .maskAlternate, .maskShift])
}

func restart() {
    post(restartKeyCode, [.maskCommand, .maskControl, .maskAlternate, .maskShift])
}
