import XCTest

final class StatusTests: XCTestCase {
    private let panel = StubStatusPanel()
    private var scheduled: [(delay: TimeInterval, block: () -> Void)] = []
    private var reads = 0
    private var trusted = true
    private var configError: ConfigError?
    private var modalIsUp = false
    private var copied: [String] = []
    private var opened: [URL] = []
    private var revealed: [URL] = []
    private var reloads = 0
    private var quits = 0
    private lazy var configDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    private lazy var configPath = configDirectory.appendingPathComponent("ottowm/ottowm")

    private lazy var status = Status(
        sources: StatusSources(
            version: { "0.0.14" },
            build: { "1287" },
            system: { "macOS 26.6.2 · Apple Silicon" },
            isTrusted: {
                self.reads += 1
                return self.trusted
            },
            hotkeysListening: { true },
            secureInputHeld: { false },
            workspace: { 2 },
            display: { "2560×1440" },
            configPath: { self.configPath },
            createConfig: {
                try? FileManager.default.createDirectory(
                    at: self.configPath.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? "hyper-q = quit".write(to: self.configPath, atomically: true, encoding: .utf8)
            },
            configError: { self.configError },
            readSetting: { _, _ in nil }
        ),
        panel: panel,
        canShow: { !self.modalIsUp },
        schedule: { self.scheduled.append(($0, $1)) },
        copy: { self.copied.append($0) },
        open: { self.opened.append($0) },
        reveal: { self.revealed.append($0) },
        reload: {
            self.reloads += 1
            self.configError = ConfigError(line: 3, reason: .unknownAction("warp"))
        },
        quit: { self.quits += 1 }
    )

    override func setUp() {
        super.setUp()
        addTeardownBlock { try? FileManager.default.removeItem(at: self.configDirectory) }
    }

    private func tick() {
        let blocks = scheduled
        scheduled = []
        for (_, block) in blocks { block() }
    }

    func testToggleShowsTheReportReadNowAndTogglesBackToHidden() {
        status.toggle()

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.rendered.map(\.accessibilityGranted), [true])
        XCTAssertEqual(panel.rendered.map(\.configExists), [false])

        status.toggle()

        XCTAssertFalse(panel.isVisible)
    }

    func testTheReportIsReadAgainEverySecondWhileShown() {
        status.toggle()
        trusted = false

        tick()

        XCTAssertEqual(scheduled.map(\.delay), [1])
        XCTAssertEqual(panel.rendered.map(\.accessibilityGranted), [true, false])
    }

    func testTheTickStopsOnceHidden() {
        status.toggle()
        status.toggle()
        let readsWhileShown = reads

        tick()

        XCTAssertEqual(reads, readsWhileShown)
        XCTAssertEqual(scheduled.count, 0)
    }

    func testAShowWhileATickIsPendingStartsNoSecondTick() {
        status.toggle()
        status.toggle()
        status.toggle()

        tick()

        XCTAssertEqual(scheduled.count, 1)
    }

    func testNothingShowsWhileAModalAlertIsUp() {
        modalIsUp = true

        status.toggle()

        XCTAssertFalse(panel.isVisible)
    }

    func testCreateConfigRendersAgainSoTheConfigLineFollowsTheWrite() {
        status.toggle()

        status.perform(.createConfig)

        XCTAssertEqual(panel.rendered.map(\.configExists), [false, true])
    }

    func testReloadRendersAgainSoTheErrorLineFollowsTheReload() {
        status.toggle()

        status.perform(.reload)

        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(panel.rendered.map(\.configError), [nil, ConfigError(line: 3, reason: .unknownAction("warp"))])
    }

    func testTheOtherActionsAreHandedToTheirClosures() {
        status.toggle()
        let fix = Requirements.all[2]
        let url = URL(string: "https://example.com/releases")!

        status.perform(.openSettings)
        status.perform(.revealConfig)
        status.perform(.copyDiagnostics)
        status.perform(.copyFix(fix))
        status.perform(.open(url))
        status.perform(.quit)

        XCTAssertEqual(opened, [AccessibilityPermission.settingsURL, url])
        XCTAssertEqual(revealed, [configPath])
        XCTAssertEqual(copied, [panel.rendered[0].text, fix.fixCommand])
        XCTAssertEqual(quits, 1)
    }
}
