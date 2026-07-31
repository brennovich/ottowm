import XCTest

final class WindowSnapshotTests: XCTestCase {
    func testIsTabOf() {
        let base = makeSnapshot(
            1,
            appName: "Terminal",
            frame: CGRect(x: 100, y: 200, width: 800, height: 600),
            tabCount: 2
        )

        let cases: [(name: String, window: WindowSnapshot, expected: Bool)] = [
            (
                "same app and identical frame",
                makeSnapshot(2, appName: "Terminal", frame: CGRect(x: 100, y: 200, width: 800, height: 600), tabCount: 2),
                true
            ),
            (
                "y within tolerance",
                makeSnapshot(2, appName: "Terminal", frame: CGRect(x: 100, y: 210, width: 800, height: 600), tabCount: 2),
                true
            ),
            (
                "y within negative tolerance",
                makeSnapshot(2, appName: "Terminal", frame: CGRect(x: 100, y: 190, width: 800, height: 600), tabCount: 2),
                true
            ),
            (
                "y beyond tolerance",
                makeSnapshot(2, appName: "Terminal", frame: CGRect(x: 100, y: 211, width: 800, height: 600), tabCount: 2),
                false
            ),
            (
                "different x",
                makeSnapshot(2, appName: "Terminal", frame: CGRect(x: 101, y: 200, width: 800, height: 600), tabCount: 2),
                false
            ),
            (
                "different width",
                makeSnapshot(2, appName: "Terminal", frame: CGRect(x: 100, y: 200, width: 801, height: 600), tabCount: 2),
                false
            ),
            (
                "different height",
                makeSnapshot(2, appName: "Terminal", frame: CGRect(x: 100, y: 200, width: 800, height: 601), tabCount: 2),
                false
            ),
            (
                "different app",
                makeSnapshot(2, appName: "Safari", frame: CGRect(x: 100, y: 200, width: 800, height: 600), tabCount: 2),
                false
            ),
            (
                "single window without tabs",
                makeSnapshot(2, appName: "Terminal", frame: CGRect(x: 100, y: 200, width: 800, height: 600), tabCount: 1),
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

    func testLogDescription() {
        let window = makeSnapshot(42, appName: "Safari", frame: .zero)

        XCTAssertEqual(window.logDescription, "id=42 app=Safari")
    }

    func testIsTabOfWindowWithStaleSingleTabSnapshot() {
        let frame = CGRect(x: 100, y: 200, width: 800, height: 600)
        let existing = makeSnapshot(1, appName: "Terminal", frame: frame, tabCount: 1)
        let newTab = makeSnapshot(2, appName: "Terminal", frame: frame, tabCount: 2)

        XCTAssertTrue(newTab.isTab(of: existing))
    }
}
