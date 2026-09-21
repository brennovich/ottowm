import XCTest

final class BindingsTests: XCTestCase {
    private var built: [Config] = []
    private var events: [String] = []
    private var loads: [Result<Config, ConfigError>] = []
    private var handedOn: [Config] = []

    private var tapStarts = true

    private func makeBindings(_ config: Config) -> Bindings {
        let bindings = Bindings(
            config: config,
            load: { self.loads.removeFirst() },
            tap: { config in
                let tap = self.built.count
                self.built.append(config)
                return Bindings.Tap(
                    start: { self.events.append("start \(tap)"); return self.tapStarts },
                    stop: { self.events.append("stop \(tap)") }
                )
            }
        )
        bindings.startWatching { self.handedOn.append($0) }
        return bindings
    }

    func testTapsTheConfigItWasBuiltWithAndTakesTheSameTapBackAfterItWasReleased() throws {
        let config = try makeConfig(["hyper-q": .quit])
        let bindings = makeBindings(config)

        bindings.start()
        XCTAssertTrue(bindings.isRunning)
        bindings.stop()
        XCTAssertFalse(bindings.isRunning)
        bindings.start()

        XCTAssertEqual(built, [config])
        XCTAssertEqual(events, ["start 0", "stop 0", "start 0"])
        XCTAssertTrue(bindings.isRunning)
    }

    func testATapThatFailsToStartIsNotRunning() throws {
        tapStarts = false
        let bindings = makeBindings(try makeConfig(["hyper-q": .quit]))

        bindings.start()

        XCTAssertFalse(bindings.isRunning)
    }

    func testReloadReplacesTheTapWithOneOverTheNewConfigAndHandsTheConfigOn() throws {
        let reloaded = try makeConfig(["hyper-r": .restart])
        loads = [.success(reloaded)]
        let bindings = makeBindings(try makeConfig(["hyper-q": .quit]))

        bindings.start()

        XCTAssertNil(bindings.reload())
        XCTAssertEqual(built.last, reloaded)
        XCTAssertEqual(events, ["start 0", "stop 0", "start 1"])
        XCTAssertEqual(handedOn, [reloaded])
        XCTAssertNil(bindings.lastError)
    }

    func testASuccessfulReloadClearsTheErrorOfTheOneBefore() throws {
        let error = ConfigError(line: 2, reason: .unknownAction("relaunch"))
        let reloaded = try makeConfig(["hyper-r": .restart])
        loads = [.failure(error), .success(reloaded)]
        let bindings = makeBindings(try makeConfig(["hyper-q": .quit]))

        XCTAssertEqual(bindings.reload(), error)
        XCTAssertEqual(bindings.lastError, error)
        XCTAssertNil(bindings.reload())
        XCTAssertNil(bindings.lastError)
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
        XCTAssertEqual(handedOn, [])
    }
}
