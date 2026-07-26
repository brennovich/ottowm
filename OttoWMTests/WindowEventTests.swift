import AppKit
import XCTest

final class WindowEventTests: XCTestCase {
    func testShouldObserveApplication() {
        let ownPid: pid_t = 42

        let cases: [(name: String, policy: NSApplication.ActivationPolicy, pid: pid_t, expected: Bool)] = [
            ("regular foreign app is observed", .regular, 100, true),
            ("accessory app is ignored", .accessory, 100, false),
            ("prohibited app is ignored", .prohibited, 100, false),
            ("our own regular pid is ignored", .regular, ownPid, false),
        ]

        for testCase in cases {
            let result = shouldObserveApplication(
                activationPolicy: testCase.policy,
                pid: testCase.pid,
                ownPid: ownPid
            )
            XCTAssertEqual(result, testCase.expected, testCase.name)
        }
    }
}
