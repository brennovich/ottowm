import CoreGraphics

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
    private var handler: ((HotkeyAction) -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start(_ handler: @escaping (HotkeyAction) -> Void) -> Bool {
        self.handler = handler

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
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown,
              let action = hotkeyAction(
                  keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                  flags: event.flags
              )
        else { return Unmanaged.passUnretained(event) }

        handler?(action)
        return nil
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
