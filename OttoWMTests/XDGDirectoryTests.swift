import XCTest

final class XDGDirectoryTests: XCTestCase {
    func testResolvesTheDirectory() {
        let cases: [(name: String, environment: [String: String], expected: String)] = [
            ("defaults to the fallback under HOME", ["HOME": "/Users/otto"], "/Users/otto/.config"),
            ("honours the variable", ["HOME": "/Users/otto", "XDG_CONFIG_HOME": "/Users/otto/cfg"], "/Users/otto/cfg"),
            ("expands a tilde", ["HOME": "/Users/otto", "XDG_CONFIG_HOME": "~/cfg"], "/Users/otto/cfg"),
            ("ignores an empty variable", ["HOME": "/Users/otto", "XDG_CONFIG_HOME": ""], "/Users/otto/.config"),
        ]

        for testCase in cases {
            let url = XDGDirectory.url("XDG_CONFIG_HOME", orHome: ".config", environment: testCase.environment)

            XCTAssertEqual(url.path, testCase.expected, testCase.name)
        }
    }
}
