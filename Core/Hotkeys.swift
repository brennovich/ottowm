import CoreGraphics
import Dispatch

// Global hotkeys via a session CGEventTap. An event tap (instead of Carbon's
// RegisterEventHotKey) because only the raw event flags distinguish the left from
// the right Option key; matched keystrokes are consumed so they never reach the
// focused application.
final class Hotkeys {
    private let keyCodeMatcher: (Int64, CGEventFlags) -> Action?
    private let dispatch: (@escaping () -> Void) -> Void
    private let handler: (Action) -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(
        keyCodeMatcher: @escaping (Int64, CGEventFlags) -> Action?,
        dispatch: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) },
        handler: @escaping (Action) -> Void
    ) {
        self.keyCodeMatcher = keyCodeMatcher
        self.dispatch = dispatch
        self.handler = handler
    }

    func start() -> Bool {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                return Unmanaged<Hotkeys>.fromOpaque(refcon).takeUnretainedValue()
                    .handle(type: type, event: event)
            },
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
            Log.hotkey.error("event tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "userInput")), re-enabling")
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown, let action = keyCodeMatcher(
            event.getIntegerValueField(.keyboardEventKeycode),
            event.flags
        ) else { return Unmanaged.passUnretained(event) }

        Log.hotkey.info("hotkey → \(action)")
        // macOS disables a tap whose callback does not return promptly, so the
        // action runs after the callback has already consumed the keystroke and
        // returned.
        dispatch { [weak self] in self?.handler(action) }
        return nil
    }

    deinit {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
    }
}
