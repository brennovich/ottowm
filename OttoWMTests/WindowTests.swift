import XCTest

final class WindowTests: XCTestCase {
    func testIsTabOf() {
        let base = StubWindow(
            id: 1,
            tabCount: 2,
            frame: CGRect(x: 100, y: 200, width: 800, height: 600),
            appName: "Terminal"
        )

        let cases: [(name: String, window: StubWindow, expected: Bool)] = [
            (
                "same app and identical frame",
                StubWindow(id: 2, tabCount: 2, frame: CGRect(x: 100, y: 200, width: 800, height: 600), appName: "Terminal"),
                true
            ),
            (
                "y within tolerance",
                StubWindow(id: 2, tabCount: 2, frame: CGRect(x: 100, y: 210, width: 800, height: 600), appName: "Terminal"),
                true
            ),
            (
                "y within negative tolerance",
                StubWindow(id: 2, tabCount: 2, frame: CGRect(x: 100, y: 190, width: 800, height: 600), appName: "Terminal"),
                true
            ),
            (
                "y beyond tolerance",
                StubWindow(id: 2, tabCount: 2, frame: CGRect(x: 100, y: 211, width: 800, height: 600), appName: "Terminal"),
                false
            ),
            (
                "different x",
                StubWindow(id: 2, tabCount: 2, frame: CGRect(x: 101, y: 200, width: 800, height: 600), appName: "Terminal"),
                false
            ),
            (
                "different width",
                StubWindow(id: 2, tabCount: 2, frame: CGRect(x: 100, y: 200, width: 801, height: 600), appName: "Terminal"),
                false
            ),
            (
                "different height",
                StubWindow(id: 2, tabCount: 2, frame: CGRect(x: 100, y: 200, width: 800, height: 601), appName: "Terminal"),
                false
            ),
            (
                "different app",
                StubWindow(id: 2, tabCount: 2, frame: CGRect(x: 100, y: 200, width: 800, height: 600), appName: "Safari"),
                false
            ),
            (
                "single window without tabs",
                StubWindow(id: 2, tabCount: 1, frame: CGRect(x: 100, y: 200, width: 800, height: 600), appName: "Terminal"),
                false
            ),
        ]

        for testCase in cases {
            XCTAssertEqual(
                testCase.window.isTab(of: base),
                testCase.expected,
                testCase.name
            )
        }
    }

    func testIsTabOfWindowWithStaleSingleTabSnapshot() {
        let frame = CGRect(x: 100, y: 200, width: 800, height: 600)
        let existing = StubWindow(id: 1, tabCount: 1, frame: frame, appName: "Terminal")
        let newTab = StubWindow(id: 2, tabCount: 2, frame: frame, appName: "Terminal")

        XCTAssertTrue(newTab.isTab(of: existing))
    }
}
