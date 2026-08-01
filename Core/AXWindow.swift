import AppKit
import ApplicationServices
import CoreGraphics

// The stable CGWindowID for an AX window (same one AeroSpace relies on).
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout CGWindowID) -> AXError

// A live macOS window driven through Accessibility.
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

    // Every attribute the model needs, in one round trip — except the tab count,
    // which has to walk the window's children.
    func snapshot() -> WindowSnapshot {
        let attributes = values([
            kAXSubroleAttribute as String,
            "AXFullScreen",
            kAXMinimizedAttribute as String,
            kAXPositionAttribute as String,
            kAXSizeAttribute as String,
        ])

        return WindowSnapshot(
            id: id,
            appName: appName,
            isStandard: attributes[0] as? String == kAXStandardWindowSubrole,
            isFullScreen: (attributes[1] as? Bool) ?? false,
            isMinimized: (attributes[2] as? Bool) ?? false,
            tabCount: tabCount,
            frame: frame(position: attributes[3], size: attributes[4]) ?? .zero
        )
    }

    func movableFrame() -> CGRect? {
        let attributes = values([
            kAXMinimizedAttribute as String,
            kAXPositionAttribute as String,
            kAXSizeAttribute as String,
        ])

        guard (attributes[0] as? Bool) != true else { return nil }
        return frame(position: attributes[1], size: attributes[2])
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
        let systemWide = AXUIElementCreateSystemWide()

        var app: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &app) == .success,
              let appElement = app.map({ $0 as! AXUIElement })
        else { return nil }

        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let windowElement = window.map({ $0 as! AXUIElement })
        else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(appElement, &pid) == .success,
              let runningApp = NSRunningApplication(processIdentifier: pid)
        else { return nil }

        return AXWindow(element: windowElement, application: runningApp)
    }

    private var tabCount: Int {
        guard let children = value(kAXChildrenAttribute) as? [AXUIElement] else {
            Log.window.debug("tabCount children read failed \(self.logDescription), assuming 1")
            return 1
        }

        for child in children {
            let attributes = values([kAXRoleAttribute as String, kAXChildrenAttribute as String], of: child)
            guard attributes[0] as? String == "AXTabGroup",
                  let tabs = attributes[1] as? [AXUIElement]
            else { continue }

            let count = tabs.filter { string(kAXRoleAttribute, of: $0) == "AXRadioButton" }.count
            return count > 0 ? count : 1
        }

        return 1
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

    private func value(_ attribute: String, of element: AXUIElement? = nil) -> CFTypeRef? {
        var result: CFTypeRef?
        let target = element ?? self.element
        guard AXUIElementCopyAttributeValue(target, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    // One round trip for several attributes instead of one each. Returns a slot
    // per requested attribute, nil where the read failed.
    private func values(_ attributes: [String], of element: AXUIElement? = nil) -> [AnyObject?] {
        var result: CFArray?
        let target = element ?? self.element
        let status = AXUIElementCopyMultipleAttributeValues(
            target, attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &result
        )
        guard status == .success, let raw = result as? [AnyObject], raw.count == attributes.count else {
            return Array(repeating: nil, count: attributes.count)
        }
        return discardingAXErrors(raw)
    }

    private func string(_ attribute: String, of element: AXUIElement? = nil) -> String? {
        value(attribute, of: element) as? String
    }
}
