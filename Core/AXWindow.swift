import AppKit
import ApplicationServices
import CoreGraphics

// The stable CGWindowID for an AX window.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout CGWindowID) -> AXError

final class AXWindow: Window {
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
        let result = _AXUIElementGetWindow(element, &windowId)
        if result != .success || windowId == 0 {
            Log.window.debug("window id lookup failed app=\(self.appName) err=\(result.rawValue)")
        }
        return windowId
    }()

    var appName: String { application.localizedName ?? "" }

    var logDescription: String { "id=\(id) app=\(appName)" }

    func snapshot() -> WindowSnapshot {
        let attributes = axAttributes(element, [
            kAXSubroleAttribute,
            kAXCloseButtonAttribute,
            kAXMinimizeButtonAttribute,
            FullScreenAttribute,
            kAXMinimizedAttribute,
            kAXPositionAttribute,
            kAXSizeAttribute,
        ])

        return WindowSnapshot(
            id: id,
            appName: appName,
            isStandard: attributes[kAXSubroleAttribute] as? String == kAXStandardWindowSubrole,
            hasCloseButton: attributes[kAXCloseButtonAttribute] != nil,
            hasMinimizeButton: attributes[kAXMinimizeButtonAttribute] != nil,
            isFullScreen: (attributes[FullScreenAttribute] as? Bool) ?? false,
            isMinimized: (attributes[kAXMinimizedAttribute] as? Bool) ?? false,
            frame: frame(position: attributes[kAXPositionAttribute], size: attributes[kAXSizeAttribute]) ?? .zero
        )
    }

    func movableFrame() -> CGRect? {
        let attributes = axAttributes(element, [kAXMinimizedAttribute, kAXPositionAttribute, kAXSizeAttribute])
        guard (attributes[kAXMinimizedAttribute] as? Bool) != true else { return nil }

        return frame(position: attributes[kAXPositionAttribute], size: attributes[kAXSizeAttribute])
    }

    func setPosition(_ origin: CGPoint) {
        let result = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, encodeCGPoint(origin))
        if result != .success {
            Log.window.error("set position failed \(self.logDescription) err=\(result.rawValue) target=\(origin)")
        }
    }

    func setSize(_ size: CGSize) {
        let result = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, encodeCGSize(size))
        if result != .success {
            Log.window.error("set size failed \(self.logDescription) err=\(result.rawValue) target=\(size)")
        }
    }

    func focus() {
        let raiseResult = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        let mainResult = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        let activated = application.activate()
        if raiseResult != .success || mainResult != .success {
            Log.window.error("focus failed \(self.logDescription) raise=\(raiseResult.rawValue) main=\(mainResult.rawValue)")
        } else if !activated {
            Log.window.debug("focus \(self.logDescription): application did not activate")
        }
    }

    static func focused() -> AXWindow? {
        NSWorkspace.shared.frontmostApplication.flatMap(focused(of:))
    }

    static func focused(of app: NSRunningApplication) -> AXWindow? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = axElement(appElement, kAXFocusedWindowAttribute) else { return nil }
        return AXWindow(element: element, application: app)
    }

    func tabCount() -> Int {
        guard let children = axAttribute(element, kAXChildrenAttribute) as? [AXUIElement] else {
            Log.window.debug("tabCount children read failed \(self.logDescription), assuming 1")
            return 1
        }
        return children.lazy
            .compactMap(tabGroupTabs)
            .first
            .map { max($0.filter(isRadioButton).count, 1) } ?? 1
    }

    private func isRadioButton(_ element: AXUIElement) -> Bool {
        axAttribute(element, kAXRoleAttribute) as? String == RadioButtonRole
    }

    private func tabGroupTabs(of child: AXUIElement) -> [AXUIElement]? {
        let attributes = axAttributes(child, [kAXRoleAttribute, kAXChildrenAttribute])
        guard attributes[kAXRoleAttribute] as? String == TabGroupRole else { return nil }
        return attributes[kAXChildrenAttribute] as? [AXUIElement]
    }

    private func frame(position: AnyObject?, size: AnyObject?) -> CGRect? {
        guard let origin = axValue(position).flatMap(decodeCGPoint),
              let size = axValue(size).flatMap(decodeCGSize)
        else {
            Log.window.error("read frame failed \(self.logDescription)")
            return nil
        }
        return CGRect(origin: origin, size: size)
    }
}
