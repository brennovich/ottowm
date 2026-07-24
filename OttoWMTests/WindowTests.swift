import XCTest

final class WindowTests: XCTestCase {
    func testIsTabOf() {
        let base = Window(
            id: 1,
            tabCount: 2,
            frame: CGRect(x: 100, y: 200, width: 800, height: 600),
            appName: "Terminal"
        )

        let cases: [(name: String, window: Window, expected: Bool)] = [
            (
                "same app and identical frame",
                Window(id: 2, tabCount: 2, frame: CGRect(x: 100, y: 200, width: 800, height: 600), appName: "Terminal"),
                true
            ),
            (
                "y within tolerance",
                Window(id: 2, tabCount: 2, frame: CGRect(x: 100, y: 210, width: 800, height: 600), appName: "Terminal"),
                true
            ),
            (
                "y within negative tolerance",
                Window(id: 2, tabCount: 2, frame: CGRect(x: 100, y: 190, width: 800, height: 600), appName: "Terminal"),
                true
            ),
            (
                "y beyond tolerance",
                Window(id: 2, tabCount: 2, frame: CGRect(x: 100, y: 211, width: 800, height: 600), appName: "Terminal"),
                false
            ),
            (
                "different x",
                Window(id: 2, tabCount: 2, frame: CGRect(x: 101, y: 200, width: 800, height: 600), appName: "Terminal"),
                false
            ),
            (
                "different width",
                Window(id: 2, tabCount: 2, frame: CGRect(x: 100, y: 200, width: 801, height: 600), appName: "Terminal"),
                false
            ),
            (
                "different height",
                Window(id: 2, tabCount: 2, frame: CGRect(x: 100, y: 200, width: 800, height: 601), appName: "Terminal"),
                false
            ),
            (
                "different app",
                Window(id: 2, tabCount: 2, frame: CGRect(x: 100, y: 200, width: 800, height: 600), appName: "Safari"),
                false
            ),
            (
                "single window without tabs",
                Window(id: 2, tabCount: 1, frame: CGRect(x: 100, y: 200, width: 800, height: 600), appName: "Terminal"),
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
        let existing = Window(id: 1, tabCount: 1, frame: frame, appName: "Terminal")
        let newTab = Window(id: 2, tabCount: 2, frame: frame, appName: "Terminal")

        XCTAssertTrue(newTab.isTab(of: existing))
    }
}
