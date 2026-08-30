import AppKit
import ApplicationServices
import CoreGraphics

// Unexported symbol to retrieve the CGWindowID that ties an AX element to the
// window server list.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout CGWindowID) -> AXError

/// A live macOS application's window reached driven the Accessibility API.
///
/// Keeps the element and its application because the interface is split between
/// them. Attributes, actions and the window id come from the element; activation
/// and `AXEnhancedUserInterface` are only on the application. Every read
/// and write is a round trip into the owning process, so attributes are read in
/// batches and the id is read once.
final class AXWindow: Window, WindowLogDescribing {
    let element: AXUIElement
    let application: NSRunningApplication

    init(element: AXUIElement, application: NSRunningApplication) {
        self.element = element
        self.application = application
    }

    convenience init(element: AXUIElement, application: NSRunningApplication, id: CGWindowID) {
        self.init(element: element, application: application)
        self.id = id
    }

    lazy var id: CGWindowID = {
        var windowId: CGWindowID = 0
        let result = trace(.read, "AXWindowID") {
            _AXUIElementGetWindow(element, &windowId)
        }
        if result != .success || windowId == 0 {
            Log.window.debug("window id lookup failed app=\(self.appName) err=\(result.rawValue)")
        }
        return windowId
    }()

    var appName: String { application.localizedName ?? "" }
    var pid: pid_t { application.processIdentifier }

    func snapshot() -> WindowSnapshot {
        let attributes = element.values(of: [
            .subrole,
            .closeButton,
            .minimizeButton,
            .fullScreen,
            .minimized,
            .position,
            .size,
        ])

        return WindowSnapshot(
            id: id,
            appName: appName,
            isStandard: AXRole(attributes[.subrole]) == .standardWindow,
            hasCloseButton: attributes[.closeButton] != nil,
            hasMinimizeButton: attributes[.minimizeButton] != nil,
            isFullScreen: (attributes[.fullScreen] as? Bool) ?? false,
            isMinimized: (attributes[.minimized] as? Bool) ?? false,
            frame: frame(position: attributes[.position], size: attributes[.size]) ?? .zero
        )
    }

    func movableFrame() -> CGRect? {
        let attributes = element.values(of: [.minimized, .position, .size])
        guard (attributes[.minimized] as? Bool) != true else { return nil }

        return frame(position: attributes[.position], size: attributes[.size])
    }

    /// An application animates a frame write while `AXEnhancedUserInterface` is on.
    /// macOS turns that attribute on as soon as an assistive client attaches.
    /// Also, A read mid animation returns the old position.
    ///
    /// Credited to yabai and Rectangle, via AeroSpace.
    func withoutAnimations(_ body: () -> Void) {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let enhanced = appElement.value(of: .enhancedUserInterface) as? Bool == true

        if enhanced { setEnhancedUserInterface(appElement, false) }
        body()
        if enhanced { setEnhancedUserInterface(appElement, true) }
    }

    func setPosition(_ origin: CGPoint) {
        let result = element.setValue(origin, for: .position)
        if result != .success {
            Log.window.error("set position failed \(self.logDescription) err=\(result.rawValue) target=\(origin)")
        }
    }

    func setSize(_ size: CGSize) {
        let result = element.setValue(size, for: .size)
        if result != .success {
            Log.window.error("set size failed \(self.logDescription) err=\(result.rawValue) target=\(size)")
        }
    }

    func focus() {
        let raiseResult = trace(.action, kAXRaiseAction) {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
        let mainResult = element.setValue(true, for: .main)
        let activated = trace(.action, "activate") {
            application.activate(options: AXWindow.activationOptions)
        }
        if raiseResult != .success || mainResult != .success {
            Log.window.error("focus failed \(self.logDescription) raise=\(raiseResult.rawValue) main=\(mainResult.rawValue)")
        } else if !activated {
            Log.window.debug("focus \(self.logDescription): application did not activate")
        }
    }

    static func focused() -> AXWindow? {
        trace(.read, "frontmostApplication") { NSWorkspace.shared.frontmostApplication }
            .flatMap(focused(of:))
    }

    static func all(of app: NSRunningApplication) -> [AXWindow] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let elements = appElement.value(of: .windows) as? [AXUIElement] ?? []
        return elements.map { AXWindow(element: $0, application: app) }
    }

    static func focused(of app: NSRunningApplication) -> AXWindow? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = appElement.elementValue(of: .focusedWindow) else { return nil }
        return AXWindow(element: element, application: app)
    }

    func tabCount() -> Int {
        guard let children = element.value(of: .children) as? [AXUIElement] else {
            Log.window.debug("tabCount children read failed \(self.logDescription), assuming 1")
            return 1
        }
        return children.lazy
            .compactMap { child -> [AXUIElement]? in
                let attributes = child.values(of: [.role, .children])
                guard AXRole(attributes[.role]) == .tabGroup else { return nil }
                return attributes[.children] as? [AXUIElement]
            }
            .first
            .map { tabs in
                max(tabs.filter { AXRole($0.value(of: .role)) == .radioButton }.count, 1)
            } ?? 1
    }

    private static var activationOptions: NSApplication.ActivationOptions {
        if #available(macOS 14.0, *) { return [] }
        return .activateIgnoringOtherApps
    }

    private func setEnhancedUserInterface(_ appElement: AXUIElement, _ enabled: Bool) {
        let result = appElement.setValue(enabled, for: .enhancedUserInterface)
        if result != .success {
            Log.window.debug("enhanced user interface \(enabled) failed \(self.logDescription) err=\(result.rawValue)")
        }
    }

    private func frame(position: AnyObject?, size: AnyObject?) -> CGRect? {
        guard let origin = CGPoint(axValue: position),
              let size = CGSize(axValue: size)
        else {
            Log.window.error("read frame failed \(self.logDescription)")
            return nil
        }
        return CGRect(origin: origin, size: size)
    }
}

/// A window is identified by its element: a new `AXWindow` is built for every notification,
/// and the id does not tell two windows apart, tabs of one group share it.
extension AXWindow: Hashable {
    static func == (lhs: AXWindow, rhs: AXWindow) -> Bool {
        lhs.element == rhs.element
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(element)
    }
}
