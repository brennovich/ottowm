import CoreGraphics
import Dispatch

// The C-convention event tap callback: trampolines back to the HotkeyEventTap carried in refcon.
private func hotkeyEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let eventTap = Unmanaged<HotkeyEventTap>.fromOpaque(refcon).takeUnretainedValue()
    return eventTap.handle(type: type, event: event)
}

// Global hotkeys via a session CGEventTap. An event tap (instead of Carbon's
// RegisterEventHotKey) because only the raw event flags distinguish the left from
// the right Option key; matched keystrokes are consumed so they never reach the
// focused application.
final class HotkeyEventTap {
    private let dispatch: (@escaping () -> Void) -> Void
    private let handler: (HotkeyAction) -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(
        dispatch: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) },
        handler: @escaping (HotkeyAction) -> Void
    ) {
        self.dispatch = dispatch
        self.handler = handler
    }

    func start() -> Bool {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: hotkeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return true
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let decision = eventTapDecision(
            type: type,
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags
        )

        switch decision {
        case .reenableAndPass:
            Log.hotkey.error("event tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "userInput")), re-enabling")
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        case let .consume(action):
            Log.hotkey.info("hotkey → \(action)")
            // macOS disables a tap whose callback does not return promptly, so the
            // action runs after the callback has already consumed the keystroke and
            // returned.
            dispatch { [weak self] in self?.handler(action) }
            return nil
        case .pass:
            return Unmanaged.passUnretained(event)
        }
    }

    deinit {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }
}
