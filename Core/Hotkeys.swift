import CoreGraphics
import Dispatch
import Foundation

// Global hotkeys via a session CGEventTap for more refined control of key events,
// such as left/right modifiers positions. The tap gets a thread of its own.
final class Hotkeys {
    private let keyCodeMatcher: (Int64, CGEventFlags) -> Action?
    private let dispatch: (@escaping () -> Void) -> Void
    private let handler: (Action) -> Void

    // Every mutable field below belongs to the tap thread once start() has handed it
    // over, so stop() asks that thread to release rather than doing it itself.
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var released = false

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
                return Unmanaged<Hotkeys>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        released = false

        // The thread publishes its run loop before start() returns, so stop() on any
        // other thread is guaranteed to find one.
        let running = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let runLoop = CFRunLoopGetCurrent()
            self?.runLoop = runLoop
            CFRunLoopAddSource(runLoop, source, .commonModes)
            running.signal()

            CFRunLoopRun()

            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        thread.name = "\(Log.subsystem).hotkeys"
        thread.qualityOfService = .userInteractive
        thread.start()
        running.wait()

        return true
    }

    // Leaves the session's event stream for good: every application's keystrokes flow
    // through this tap, so it must not stay in the way once it can no longer serve the
    // hotkeys it exists for.
    func stop() {
        guard let runLoop else {
            release()
            return
        }
        self.runLoop = nil

        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
            release()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(runLoop)
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if released { return Unmanaged.passUnretained(event) }

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

    private func release() {
        released = true

        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        self.tap = nil
    }

    // Released here and not through the tap thread: the block stop() hands over would
    // outlive the deallocation it cleans up after.
    deinit {
        let runLoop = self.runLoop
        release()
        if let runLoop { CFRunLoopStop(runLoop) }
    }
}
