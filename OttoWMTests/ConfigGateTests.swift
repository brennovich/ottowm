import XCTest

final class ConfigGateTests: XCTestCase {
    private var asked: [ConfigError] = []
    private var response: ConfigAlert.Response = .dismiss
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

    func testLoadRecoversFromAConfigThatDoesNotParse() {
        let error = ConfigError(line: 2, reason: .unknownAction("relaunch"))
        response = .restart

        XCTAssertEqual(makeGate(.failure(error)).load(), .relaunching)
        XCTAssertEqual(asked, [error])
    }

    func testRecoverRelaunchesOnRestartAndQuitsOnDismiss() {
        let error = ConfigError(line: 1, reason: .syntax("lalt-1 switch-to-workspace 1"))
        let cases: [(response: ConfigAlert.Response, outcome: ConfigGate.Outcome, relaunches: Int)] = [
            (.restart, .relaunching, 1),
            (.dismiss, .quit, 0),
        ]

        for testCase in cases {
            relaunches = 0
            response = testCase.response

            XCTAssertEqual(makeGate(.success(Config([:]))).recover(from: error), testCase.outcome)
            XCTAssertEqual(relaunches, testCase.relaunches)
        }
    }
}
