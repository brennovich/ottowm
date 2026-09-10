import AppKit
import XCTest

final class ApplicationFilterTests: XCTestCase {
    func testIncludesOnlyTheApplicationsWorthASubscription() {
        let filter = ApplicationFilter(ownPid: 999)
        let cases: [(String, StubRunningApplication, Bool)] = [
            ("a regular application", StubRunningApplication(pid: 901), true),
            ("an accessory application", StubRunningApplication(pid: 902, policy: .accessory), true),
            ("an application without a bundle id", StubRunningApplication(pid: 903, bundleId: nil), true),
            ("a prohibited application", StubRunningApplication(pid: 904, policy: .prohibited), false),
            ("OttoWM itself", StubRunningApplication(pid: 999), false),
            ("the lock screen", StubRunningApplication(pid: 905, bundleId: "com.apple.loginwindow"), false),
            ("WebKit content", StubRunningApplication(pid: 906, bundleId: "com.apple.WebKit.WebContent"), false),
            ("WebKit networking", StubRunningApplication(pid: 907, bundleId: "com.apple.WebKit.Networking"), false),
            ("WebKit GPU", StubRunningApplication(pid: 908, bundleId: "com.apple.WebKit.GPU"), false),
            ("Universal Control", StubRunningApplication(pid: 909, bundleId: "com.apple.universalcontrol"), false),
        ]

        for (name, app, included) in cases {
            XCTAssertEqual(filter.includes(app), included, name)
        }
    }
}
