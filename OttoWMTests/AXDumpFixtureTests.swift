import CoreGraphics
import Foundation
import XCTest

// The recorded shape of a real window, as `make axdump` wrote it. Read from the source
// tree rather than the test bundle: these are fixtures to look at and edit, not
// resources the app ships.
private struct AXDump: Decodable {
    let app: String
    let note: String
    let role: String
    let subrole: String
    let hasCloseButton: Bool
    let hasMinimizeButton: Bool
    let isFullScreen: Bool
    let isMinimized: Bool
    let id: UInt32
    let admissible: Bool

    var snapshot: WindowSnapshot {
        WindowSnapshot(
            id: id,
            appName: app,
            isStandard: subrole == kAXStandardWindowSubrole,
            hasCloseButton: hasCloseButton,
            hasMinimizeButton: hasMinimizeButton,
            isFullScreen: isFullScreen,
            isMinimized: isMinimized,
            frame: .zero
        )
    }
}

final class AXDumpFixtureTests: XCTestCase {
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/axDumps")

    private func fixtures() throws -> [(name: String, dump: AXDump)] {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.directory.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()

        return try names.map { name in
            let data = try Data(contentsOf: Self.directory.appendingPathComponent(name))
            return (name, try JSONDecoder().decode(AXDump.self, from: data))
        }
    }

    func testRecordedWindowsAreAdmittedAsRecorded() throws {
        for fixture in try fixtures() {
            XCTAssertEqual(
                fixture.dump.snapshot.isAdmissible, fixture.dump.admissible,
                "\(fixture.name): \(fixture.dump.note)"
            )
        }
    }

    func testEveryRecordedWindowThatIsAdmittedCarriesAnId() throws {
        for fixture in try fixtures() where fixture.dump.admissible {
            XCTAssertNotEqual(fixture.dump.id, 0, fixture.name)
        }
    }
}
