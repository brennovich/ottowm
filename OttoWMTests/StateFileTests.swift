import CoreGraphics
import Foundation
import XCTest

final class StateFileTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let state = SavedState(
        display: .standard,
        workspaces: Workspaces.Record(current: 2, workspaces: [:]),
        parkedWindows: [],
        originalFrames: [:],
        displayLayouts: [:]
    )

    private func stateFile(loginSession: String) -> StateFile {
        StateFile(environment: ["XDG_STATE_HOME": directory.path], loginSession: loginSession)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLivesUnderXDGStateHome() {
        let cases: [(name: String, environment: [String: String], expected: String)] = [
            ("set", ["HOME": "/Users/otto", "XDG_STATE_HOME": "/Users/otto/state"], "/Users/otto/state/ottowm/state.json"),
            ("unset", ["HOME": "/Users/otto"], "/Users/otto/.local/state/ottowm/state.json"),
        ]

        for testCase in cases {
            XCTAssertEqual(StateFile(environment: testCase.environment).url.path, testCase.expected, testCase.name)
        }
    }

    func testIdentifiesTheLoginSessionByItsAuditSessionAndTheBootTime() throws {
        let session = try XCTUnwrap(CGSessionCopyCurrentDictionary() as? [String: Any])
        let auditSession = try XCTUnwrap(session["kCGSSessionAuditIDKey"] as? Int)
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        XCTAssertEqual(sysctlbyname("kern.boottime", &bootTime, &size, nil, 0), 0)

        XCTAssertEqual(StateFile.currentLoginSession(), "\(auditSession)-\(bootTime.tv_sec).\(bootTime.tv_usec)")
    }

    func testLoadsWhatItSavedInTheCurrentLoginSession() {
        let stateFile = StateFile(environment: ["XDG_STATE_HOME": directory.path])

        stateFile.save(state)

        XCTAssertEqual(stateFile.load(), state)
    }

    func testLoadsNothingSavedInAnotherLoginSession() {
        stateFile(loginSession: "session-1").save(state)

        XCTAssertNil(stateFile(loginSession: "session-2").load())
    }

    func testLoadsNothingFromAFileThatIsMissingOrDoesNotDecode() throws {
        let stateFile = stateFile(loginSession: "session-1")
        XCTAssertNil(stateFile.load(), "missing")

        try FileManager.default.createDirectory(at: directory.appendingPathComponent("ottowm"), withIntermediateDirectories: true)
        try Data("{\"state\": 1}".utf8).write(to: stateFile.url)

        XCTAssertNil(stateFile.load(), "not a state")
    }
}
