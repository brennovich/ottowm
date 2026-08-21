import AppKit

// Only the raw event flags tell the left Option key from the right one, and the bundled
// bindings are all left Option, so the device dependent bits of Core/Config/KeyCombo.swift
// have to be set by hand. System Events cannot produce them.
let leftOptionBit: UInt64 = 0x20
let leftShiftBit: UInt64 = 0x2

let keyCodesByWorkspace: [Int: CGKeyCode] = [1: 18, 2: 19, 3: 20, 4: 21]

func post(_ keyCode: CGKeyCode, _ flags: CGEventFlags) {
    guard let source = CGEventSource(stateID: .hidSystemState) else { fail("cannot create an event source") }

    for keyDown in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
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
