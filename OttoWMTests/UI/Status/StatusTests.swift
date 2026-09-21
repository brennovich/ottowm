import XCTest

final class StatusTests: XCTestCase {
    private let panel = StubStatusPanel()
    private let notificationCenter = NotificationCenter()
    private var reads = 0
    private var trusted = true
    private var configExists = false
    private var configError: ConfigError?
    private var modalIsUp = false
    private var appIsActive = true
    private var copied: [String] = []
    private var opened: [URL] = []
    private var revealed: [URL] = []
    private var reloads = 0
    private let configPath = URL(fileURLWithPath: "/tmp/ottowm/ottowm")

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
            display: { "2560×1440" },
            configPath: { self.configPath },
            configExists: { _ in self.configExists },
            createConfig: { self.configExists = true },
            configError: { self.configError },
            readSetting: { _, _ in nil }
        ),
        panel: panel,
        notificationCenter: notificationCenter,
        canShow: { !self.modalIsUp },
        isActive: { self.appIsActive },
        copy: { self.copied.append($0) },
        open: { self.opened.append($0) },
        reveal: { self.revealed.append($0) },
        reload: {
            self.reloads += 1
            self.configError = ConfigError(line: 3, reason: .unknownAction("warp"))
        }
    )

    private func activate() {
        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    func testToggleShowsTheReportReadNowAndTogglesBackToHidden() {
        status.toggle()

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.rendered.map(\.accessibilityGranted), [true])

        status.toggle()

        XCTAssertFalse(panel.isVisible)
    }

    func testTheReportIsReadAgainWhenTheApplicationIsActivated() {
        status.toggle()
        trusted = false

        activate()

        XCTAssertEqual(panel.rendered.map(\.accessibilityGranted), [true, false])
    }

    func testTheActivationThatShowingTheWindowCausesDoesNotReadTheReportAgain() {
        appIsActive = false
        status.toggle()
        trusted = false

        activate()
        activate()

        XCTAssertEqual(panel.rendered.map(\.accessibilityGranted), [true, false])
    }

    func testNothingIsReadOnActivationWhileTheWindowIsHidden() {
        status.toggle()
        status.toggle()
        let readsWhileShown = reads

        activate()

        XCTAssertEqual(reads, readsWhileShown)
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

        status.perform(.openSettings)
        status.perform(.revealConfig)
        status.perform(.copyDiagnostics)
        status.perform(.copyFixes)

        XCTAssertEqual(opened, [AccessibilityPermission.settingsURL])
        XCTAssertEqual(revealed, [configPath])
        XCTAssertEqual(copied, [panel.rendered[0].text, panel.rendered[0].fixes])
    }
}
