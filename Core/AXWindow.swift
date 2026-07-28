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

    var isStandard: Bool { string(kAXSubroleAttribute) == kAXStandardWindowSubrole }

    var isFullScreen: Bool { bool("AXFullScreen") }

    var isMinimized: Bool { bool(kAXMinimizedAttribute as String) }

    var tabCount: Int {
        guard let children = value(kAXChildrenAttribute) as? [AXUIElement] else {
            Log.window.debug("tabCount children read failed \(logDescription), assuming 1")
            return 1
        }

        for child in children {
            guard string(kAXRoleAttribute, of: child) == "AXTabGroup",
                  let tabs = value(kAXChildrenAttribute, of: child) as? [AXUIElement]
            else { continue }

            let count = tabs.filter { string(kAXRoleAttribute, of: $0) == "AXRadioButton" }.count
            return count > 0 ? count : 1
        }

        return 1
    }

    var frame: CGRect {
        get {
            guard let positionRef = value(kAXPositionAttribute),
                  let sizeRef = value(kAXSizeAttribute),
                  let origin = decodeCGPoint(positionRef as! AXValue),
                  let size = decodeCGSize(sizeRef as! AXValue)
            else {
                Log.window.error("read frame failed \(logDescription)")
                return .zero
            }
            return CGRect(origin: origin, size: size)
        }
        set {
            let positionResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, encodeCGPoint(newValue.origin))
            let sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, encodeCGSize(newValue.size))
            if positionResult != .success || sizeResult != .success {
                Log.window.error("set frame failed \(logDescription) position=\(positionResult.rawValue) size=\(sizeResult.rawValue) target=\(newValue)")
            }
        }
    }

    func focus() {
        let raiseResult = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        let mainResult = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        let activated = application.activate()
        if raiseResult != .success || mainResult != .success || !activated {
            Log.window.error("focus failed \(logDescription) raise=\(raiseResult.rawValue) main=\(mainResult.rawValue) activate=\(activated)")
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

    private func value(_ attribute: String, of element: AXUIElement? = nil) -> CFTypeRef? {
        var result: CFTypeRef?
        let target = element ?? self.element
        guard AXUIElementCopyAttributeValue(target, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private func string(_ attribute: String, of element: AXUIElement? = nil) -> String? {
        value(attribute, of: element) as? String
    }

    private func bool(_ attribute: String, of element: AXUIElement? = nil) -> Bool {
        (value(attribute, of: element) as? Bool) ?? false
    }
}
