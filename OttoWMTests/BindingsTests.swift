import XCTest

final class BindingsTests: XCTestCase {
    private var built: [Config] = []
    private var events: [String] = []
    private var loads: [Result<Config, ConfigError>] = []

    private func makeBindings(_ config: Config) -> Bindings {
        Bindings(
            config: config,
            load: { self.loads.removeFirst() },
            tap: { config in
                let tap = self.built.count
                self.built.append(config)
                return Bindings.Tap(
                    start: { self.events.append("start \(tap)"); return true },
                    stop: { self.events.append("stop \(tap)") }
                )
            }
        )
    }

    func testTapsTheConfigItWasBuiltWithAndTakesTheSameTapBackAfterItWasReleased() throws {
        let config = try makeConfig(["hyper-q": .quit])
        let bindings = makeBindings(config)

        bindings.start()
        bindings.stop()
        bindings.start()

        XCTAssertEqual(built, [config])
        XCTAssertEqual(events, ["start 0", "stop 0", "start 0"])
    }

    func testReloadReplacesTheTapWithOneOverTheNewConfig() throws {
        let reloaded = try makeConfig(["hyper-r": .restart])
        loads = [.success(reloaded)]
        let bindings = makeBindings(try makeConfig(["hyper-q": .quit]))

        bindings.start()

        XCTAssertNil(bindings.reload())
        XCTAssertEqual(built.last, reloaded)
        XCTAssertEqual(events, ["start 0", "stop 0", "start 1"])
    }

    func testReloadReportsTheErrorAndKeepsTheBindingsAlreadyUpWhenTheConfigDoesNotParse() throws {
        let error = ConfigError(line: 2, reason: .unknownAction("relaunch"))
        loads = [.failure(error)]
        let config = try makeConfig(["hyper-q": .quit])
        let bindings = makeBindings(config)

        bindings.start()

        XCTAssertEqual(bindings.reload(), error)
        XCTAssertEqual(built, [config])
        XCTAssertEqual(events, ["start 0"])
    }
}
