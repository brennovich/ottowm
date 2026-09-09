import CoreGraphics

// Only the raw event flags tell the left Option key from the right one, and the bundled
// workspace bindings are all left Option, so the device dependent bits of
// Core/Input/KeyCombo.swift have to be set by hand. System Events cannot produce them.
// The bundled quit and restart bindings are hyper, which takes either side of every
// modifier, so the masks alone match them.
let leftOptionBit: UInt64 = 0x20
let leftShiftBit: UInt64 = 0x2

// The bundled bindings name the left Option key, so every combo carries its device bit.
// `ctrl` and `shift` are named without a side, and Core/Input/KeyCombo.swift matches
// those on the mask alone.
let leftOption = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | leftOptionBit)
let leftOptionShift = CGEventFlags(
    rawValue: leftOption.rawValue | CGEventFlags.maskShift.rawValue | leftShiftBit
)
let leftOptionControl = CGEventFlags(rawValue: leftOption.rawValue | CGEventFlags.maskControl.rawValue)
let leftOptionControlShift = CGEventFlags(rawValue: leftOptionShift.rawValue | CGEventFlags.maskControl.rawValue)

let keyCodesByWorkspace: [Int: CGKeyCode] = [1: 18, 2: 19, 3: 20, 4: 21, 5: 23]
let quitKeyCode: CGKeyCode = 12
let restartKeyCode: CGKeyCode = 15
// Core/Input/Action.swift moves a window 15 points when the binding names no distance,
// which the bundled move-window bindings do not.
let moveWindowStep: CGFloat = 15

let centerKeyCode: CGKeyCode = 8
let maximizeKeyCode: CGKeyCode = 46

// The h/j/k/l the bundled focus, move-window and fill bindings share in
// Core/Input/ottowm, told apart by the modifiers each one carries.
enum Direction: String {
    case north, east, south, west
}

let keyCodesByDirection: [Direction: CGKeyCode] = [.west: 4, .south: 38, .north: 40, .east: 37]

// The same h/j/k/l under Control and Shift, as the bundled resize bindings name them.
enum ResizeChange: String {
    case wider, narrower, taller, shorter
}

let keyCodesByResizeChange: [ResizeChange: CGKeyCode] = [.narrower: 4, .taller: 38, .shorter: 40, .wider: 37]

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
    post(keyCode(forWorkspace: workspace), leftOption)
}

func moveWindowToWorkspace(_ workspace: Int) {
    post(keyCode(forWorkspace: workspace), leftOptionShift)
}

func keyCode(for direction: Direction, action: String) -> CGKeyCode {
    guard let keyCode = keyCodesByDirection[direction] else {
        fail("no key bound to \(action) \(direction.rawValue)")
    }
    return keyCode
}

func focusNeighbor(_ direction: Direction) {
    post(keyCode(for: direction, action: "focus"), leftOption)
}

func moveWindow(_ direction: Direction) {
    post(keyCode(for: direction, action: "move-window"), leftOptionShift)
}

func resizeWindow(_ change: ResizeChange) {
    guard let keyCode = keyCodesByResizeChange[change] else { fail("no key bound to resize \(change.rawValue)") }
    post(keyCode, leftOptionControlShift)
}

func fillHalf(_ direction: Direction) {
    post(keyCode(for: direction, action: "fill"), leftOptionControl)
}

func centerWindow() {
    post(centerKeyCode, leftOptionControl)
}

func toggleMaximize() {
    post(maximizeKeyCode, leftOptionControl)
}

func quit() {
    post(quitKeyCode, [.maskCommand, .maskControl, .maskAlternate, .maskShift])
}

func restart() {
    post(restartKeyCode, [.maskCommand, .maskControl, .maskAlternate, .maskShift])
}
