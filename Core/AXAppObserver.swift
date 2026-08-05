import ApplicationServices

// One observed application's AX subscription surface: what to watch and how to let go.
struct AppObserver {
    // Answers whether the subscription is in place, so a caller that depends on the
    // notification can retry rather than stay deaf for the application's lifetime.
    let watch: (AXUIElement, String) -> Bool
    let invalidate: () -> Void
}

private final class CallbackBox {
    let callback: (AXUIElement, String) -> Void

    init(_ callback: @escaping (AXUIElement, String) -> Void) {
        self.callback = callback
    }
}

// The C-convention AXObserver callback: trampolines to the Swift closure carried in refcon.
private func axObserverCallback(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?)
{
    guard let refcon else { return }

    let box = Unmanaged<CallbackBox>.fromOpaque(refcon).takeUnretainedValue()
    box.callback(element, notification as String)
}

// The real AXObserver machinery behind AppObserver: creation, the refcon
// trampoline (bridging a C callback API to object-oriented/closure-based code)
// and the main run loop source.
enum AXAppObserver {
    static func make(pid: pid_t, callback: @escaping (AXUIElement, String) -> Void) -> AppObserver? {
        var observer: AXObserver?
        let createResult = AXObserverCreate(pid, axObserverCallback, &observer)
        guard createResult == .success, let observer else {
            Log.observer.error("cannot observe pid=\(pid) err=\(createResult.rawValue)")
            return nil
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        let box = Unmanaged.passRetained(CallbackBox(callback))

        return AppObserver(
            watch: { element, notification in
                let result = AXObserverAddNotification(observer, element, notification as CFString, box.toOpaque())
                if result == .success || result == .notificationAlreadyRegistered { return true }

                Log.observer.error("addNotification \(notification) failed pid=\(pid) err=\(result.rawValue)")
                return false
            },
            invalidate: {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
                box.release()
            }
        )
    }
}
