import XCTest

final class ShutdownTests: XCTestCase {
    private var events: [String] = []
    private var terminated: (() -> Void)?

    private func makeShutdown() -> Shutdown {
        Shutdown(
            stop: { self.events.append("stop") },
            exit: { self.events.append("exit \($0)") },
            observeSIGTERM: { self.terminated = $0; return nil }
        )
    }

    func testQuitLeavesTheRestoreToTheEngine() {
        makeShutdown().quit()

        XCTAssertEqual(events, ["exit 0"])
    }

    func testSIGTERMRestoresTheWindowsBeforeItExits() throws {
        let shutdown = makeShutdown()

        shutdown.startWatchingSIGTERM()
        XCTAssertEqual(events, [])

        try XCTUnwrap(terminated)()

        XCTAssertEqual(events, ["stop", "exit 0"])
    }
}
