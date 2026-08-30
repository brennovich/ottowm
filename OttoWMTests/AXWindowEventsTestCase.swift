import AppKit
import ApplicationServices
import CoreGraphics
import XCTest

/// The fixture the `AXWindowEvents` test cases share: one harness over one application,
/// and the events the window events report.
class AXWindowEventsTestCase: XCTestCase {
    let harness = AXWindowEventsHarness()
    let app = StubRunningApplication(pid: 901)
    var events: [WindowEvent] = []

    lazy var windowEvents = harness.windowEvents
    lazy var applications = harness.applications

    override func setUp() {
        super.setUp()
        windowEvents.onEvent = { [weak self] in self?.events.append($0) }
    }

    @discardableResult
    func start(_ application: NSRunningApplication? = nil) -> AXWindowEvents.Attempt? {
        windowEvents.start(application ?? app)
    }

    func notify(_ element: AXUIElement, _ notification: String, pid: pid_t = 901) {
        harness.callbacks[pid]?(element, notification)
    }
}
