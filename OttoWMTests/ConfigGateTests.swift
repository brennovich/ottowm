import XCTest

final class ConfigGateTests: XCTestCase {
    private var asked: [ConfigError] = []
    private var response: ConfigAlert.Response = .quit
    private var relaunches = 0

    private func makeGate(_ result: Result<Config, ConfigError>) -> ConfigGate {
        ConfigGate(
            read: { result },
            ask: { error in
                self.asked.append(error)
                return self.response
            },
            relaunch: { self.relaunches += 1 }
        )
    }

    func testHandsOverTheConfigWhenItParses() throws {
        let config = try makeConfig(["hyper-q": .quit])

        XCTAssertEqual(makeGate(.success(config)).load(), .loaded(config))
        XCTAssertEqual(asked, [])
        XCTAssertEqual(relaunches, 0)
    }

    func testRelaunchesWhenTheUserRestartsOverTheError() {
        let error = ConfigError(line: 2, reason: .unknownAction("relaunch"))
        response = .restart

        XCTAssertEqual(makeGate(.failure(error)).load(), .relaunching)
        XCTAssertEqual(asked, [error])
        XCTAssertEqual(relaunches, 1)
    }

    func testQuitsWhenTheUserDismissesTheError() {
        let error = ConfigError(line: 1, reason: .syntax("lalt-1 switch-to-workspace 1"))
        response = .quit

        XCTAssertEqual(makeGate(.failure(error)).load(), .quit)
        XCTAssertEqual(asked, [error])
        XCTAssertEqual(relaunches, 0)
    }
}
