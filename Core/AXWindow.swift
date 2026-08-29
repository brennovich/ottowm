import AppKit
import ApplicationServices
import CoreGraphics

/// The stable CGWindowID for an AX window.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout CGWindowID) -> AXError

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
        let result = RoundTrips.shared.measure(.read, "AXWindowID") {
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

    /// Runs `body` with the application's frame animations turned off.
    ///
    /// An application animates a frame write while AXEnhancedUserInterface is on. macOS
    /// turns that attribute on as soon as an assistive client like OttoWM attaches. The
    /// move flickers, and a frame read mid animation returns the old position.
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
        let raiseResult = RoundTrips.shared.measure(.action, kAXRaiseAction) {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
        let mainResult = element.setValue(true, for: .main)
        let activated = RoundTrips.shared.measure(.action, "activate") {
            application.activate(options: AXWindow.activationOptions)
        }
        if raiseResult != .success || mainResult != .success {
            Log.window.error("focus failed \(self.logDescription) raise=\(raiseResult.rawValue) main=\(mainResult.rawValue)")
        } else if !activated {
            Log.window.debug("focus \(self.logDescription): application did not activate")
        }
    }

    static func focused() -> AXWindow? {
        RoundTrips.shared
            .measure(.read, "frontmostApplication") { NSWorkspace.shared.frontmostApplication }
            .flatMap(focused(of:))
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
            .compactMap(tabGroupTabs)
            .first
            .map { max($0.filter(isRadioButton).count, 1) } ?? 1
    }

    /// Required to activate an app from a background agent prior to macOS 14.
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

    private func isRadioButton(_ element: AXUIElement) -> Bool {
        AXRole(element.value(of: .role)) == .radioButton
    }

    private func tabGroupTabs(of child: AXUIElement) -> [AXUIElement]? {
        let attributes = child.values(of: [.role, .children])
        guard AXRole(attributes[.role]) == .tabGroup else { return nil }
        return attributes[.children] as? [AXUIElement]
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
