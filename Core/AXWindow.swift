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
            kAXSubroleAttribute as String,
            "AXFullScreen",
            kAXMinimizedAttribute as String,
            kAXPositionAttribute as String,
            kAXSizeAttribute as String,
        ])

        return WindowSnapshot(
            id: id,
            appName: appName,
            isStandard: attributes[kAXSubroleAttribute as String] as? String == kAXStandardWindowSubrole,
            isFullScreen: (attributes["AXFullScreen"] as? Bool) ?? false,
            isMinimized: (attributes[kAXMinimizedAttribute as String] as? Bool) ?? false,
            tabCount: tabCount,
            frame: frame(position: attributes[kAXPositionAttribute as String], size: attributes[kAXSizeAttribute as String]) ?? .zero
        )
    }

    func movableFrame() -> CGRect? {
        let attributes = axAttributes(element, [
            kAXMinimizedAttribute as String,
            kAXPositionAttribute as String,
            kAXSizeAttribute as String,
        ])

        guard (attributes[kAXMinimizedAttribute as String] as? Bool) != true else { return nil }
        return frame(position: attributes[kAXPositionAttribute as String], size: attributes[kAXSizeAttribute as String])
    }

    func setFrame(_ frame: CGRect) {
        let positionResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, encodeCGPoint(frame.origin))
        let sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, encodeCGSize(frame.size))
        if positionResult != .success || sizeResult != .success {
            Log.window.error("set frame failed \(self.logDescription) position=\(positionResult.rawValue) size=\(sizeResult.rawValue) target=\(frame)")
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
        axElement(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute)
            .flatMap(axPid)
            .flatMap(NSRunningApplication.init(processIdentifier:))
            .flatMap(focused(of:))
    }

    static func focused(of app: NSRunningApplication) -> AXWindow? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = axElement(appElement, kAXFocusedWindowAttribute) else { return nil }
        return AXWindow(element: element, application: app)
    }

    private var tabCount: Int {
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
        axAttribute(element, kAXRoleAttribute) as? String == "AXRadioButton"
    }

    private func tabGroupTabs(of child: AXUIElement) -> [AXUIElement]? {
        let attributes = axAttributes(child, [kAXRoleAttribute as String, kAXChildrenAttribute as String])
        guard attributes[kAXRoleAttribute as String] as? String == "AXTabGroup" else { return nil }
        return attributes[kAXChildrenAttribute as String] as? [AXUIElement]
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
