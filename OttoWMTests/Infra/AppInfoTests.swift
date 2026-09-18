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

    func testVersionComesFromTheBundle() throws {
        let bundle = try makeBundle(info: ["CFBundleShortVersionString": "9.9.9"])

        XCTAssertEqual(AppInfo.version(bundle), "9.9.9")
    }

    func testVersionFallsBackWhenTheBundleDeclaresNone() throws {
        let bundle = try makeBundle(info: nil)

        XCTAssertEqual(AppInfo.version(bundle), "unknown")
    }
}
