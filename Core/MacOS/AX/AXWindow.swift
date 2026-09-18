import AppKit
import ApplicationServices
import CoreGraphics

/// A window of a running application, driven through the Accessibility API.
///
/// Holds the element and its application because the API is split between them:
/// attributes, actions and the window id come from the element, activation and
/// `AXEnhancedUserInterface` only from the application.
///
/// Every read and write is a round trip into the owning process, so attributes are
/// read in batches and the id is read once.
final class AXWindow: Window, WindowLogDescribing {
    let element: AXUIElement
    let application: NSRunningApplication
    private let access: AXAccess

    init(element: AXUIElement, application: NSRunningApplication, access: AXAccess = .live) {
        self.element = element
        self.application = application
        self.access = access
    }

    convenience init(element: AXUIElement, application: NSRunningApplication, id: CGWindowID, access: AXAccess = .live) {
        self.init(element: element, application: application, access: access)
        self.id = id
    }

    lazy var id: CGWindowID = {
        let (result, windowId) = access.windowId(element)
        if result != .success || windowId == 0 {
            Log.window.debug("window id lookup failed app=\(self.appName) err=\(result.rawValue)")
        }
        return windowId
    }()

    var appName: String { application.localizedName ?? "" }
    var pid: pid_t { application.processIdentifier }

    func snapshot() -> WindowSnapshot {
        let attributes = access.values(element, [
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
        let attributes = access.values(element, [.minimized, .position, .size])
        guard (attributes[.minimized] as? Bool) != true else { return nil }

        return frame(position: attributes[.position], size: attributes[.size])
    }

    /// An application animates a frame write while `AXEnhancedUserInterface` is on.
    /// macOS turns that attribute on as soon as an assistive client attaches, and a read
    /// mid animation returns the old position.
    ///
    /// Credited to yabai and Rectangle, via AeroSpace.
    func withoutAnimations<T>(_ body: () -> T) -> T {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let enhanced = access.copyValue(appElement, .enhancedUserInterface).value as? Bool == true

        if enhanced { setEnhancedUserInterface(appElement, false) }
        defer { if enhanced { setEnhancedUserInterface(appElement, true) } }
        return body()
    }

    func setPosition(_ origin: CGPoint) {
        let result = access.setValue(element, .position, origin.axValue)
        if result != .success {
            Log.window.error("set position failed \(self.logDescription) err=\(result.rawValue) target=\(origin)")
        }
    }

    func setSize(_ size: CGSize) {
        let result = access.setValue(element, .size, size.axValue)
        if result != .success {
            Log.window.error("set size failed \(self.logDescription) err=\(result.rawValue) target=\(size)")
        }
    }

    func focus() {
        let raiseResult = access.perform(element, kAXRaiseAction)
        let mainResult = access.setValue(element, .main, kCFBooleanTrue)
        let activated = access.activate(application)
        if raiseResult != .success || mainResult != .success {
            Log.window.error("focus failed \(self.logDescription) raise=\(raiseResult.rawValue) main=\(mainResult.rawValue)")
        } else if !activated {
            Log.window.debug("focus \(self.logDescription): application did not activate")
        }
    }

    static func focused(access: AXAccess) -> AXWindow? {
        access.frontmostApplication().flatMap { focused(of: $0, access: access) }
    }

    static func all(of app: NSRunningApplication, access: AXAccess) -> [AXWindow] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let elements = access.copyValue(appElement, .windows).value as? [AXUIElement] ?? []
        return elements.map { AXWindow(element: $0, application: app, access: access) }
    }

    static func focused(of app: NSRunningApplication, access: AXAccess) -> AXWindow? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = elementValue(access.copyValue(appElement, .focusedWindow).value) else { return nil }
        return owning(element, of: app, access: access)
    }

    /// The window a sheet belongs to, the element itself otherwise.
    ///
    /// An application reports the sheet it shows as its focused window. A sheet is absent
    /// from the window list, carries no subrole and moves with the window it belongs to, so
    /// that window is the one to act on.
    static func owning(_ element: AXUIElement, of app: NSRunningApplication, access: AXAccess) -> AXWindow {
        let isSheet = AXRole(access.copyValue(element, .role).value) == .sheet
        let owner = isSheet ? elementValue(access.copyValue(element, .window).value) : nil
        return AXWindow(element: owner ?? element, application: app, access: access)
    }

    func isAlive() -> Bool {
        access.copyValue(element, .role).status != .invalidUIElement
    }

    func tabCount() -> Int {
        guard let children = access.copyValue(element, .children).value as? [AXUIElement] else {
            Log.window.debug("tabCount children read failed \(self.logDescription), assuming 1")
            return 1
        }
        let tabs = children.lazy
            .compactMap { child -> [AXUIElement]? in
                let attributes = self.access.values(child, [.role, .children])
                guard AXRole(attributes[.role]) == .tabGroup else { return nil }
                return attributes[.children] as? [AXUIElement]
            }
            .first ?? []

        return max(tabs.filter { AXRole(access.copyValue($0, .role).value) == .radioButton }.count, 1)
    }

    private static func elementValue(_ value: AnyObject?) -> AXUIElement? {
        guard let value else { return nil }
        // swiftlint:disable:next force_cast
        return (value as! AXUIElement)
    }

    private func setEnhancedUserInterface(_ appElement: AXUIElement, _ enabled: Bool) {
        let result = access.setValue(appElement, .enhancedUserInterface, enabled ? kCFBooleanTrue : kCFBooleanFalse)
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

/// A window is identified by its element: tabs of one group share an id.
extension AXWindow: Hashable {
    static func == (lhs: AXWindow, rhs: AXWindow) -> Bool {
        lhs.element == rhs.element
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(element)
    }
}
