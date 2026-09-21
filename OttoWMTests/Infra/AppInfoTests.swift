import XCTest

final class AppInfoTests: XCTestCase {
    private func makeBundle(info: [String: String]?) throws -> Bundle {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        if let info {
            try (info as NSDictionary).write(to: url.appendingPathComponent("Info.plist"))
        }

        return try XCTUnwrap(Bundle(url: url))
    }

    func testTheValueComesFromTheBundleAndFallsBackWhenItDeclaresNone() throws {
        let cases: [(name: String, info: [String: String]?, read: (Bundle) -> String, value: String)] = [
            ("version", ["CFBundleShortVersionString": "9.9.9"], AppInfo.version, "9.9.9"),
            ("version, none declared", nil, AppInfo.version, "unknown"),
            ("build", ["CFBundleVersion": "1287"], AppInfo.build, "1287"),
            ("build, none declared", nil, AppInfo.build, "unknown"),
        ]

        for testCase in cases {
            XCTAssertEqual(testCase.read(try makeBundle(info: testCase.info)), testCase.value, testCase.name)
        }
    }
}
