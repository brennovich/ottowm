import AppKit

/// The About window: reads the report when shown and once a second while it stays up, and runs its buttons.
final class Status {
    private static let refreshInterval: TimeInterval = 1

    private let sources: StatusSources
    private let panel: any StatusPanel
    private let canShow: () -> Bool
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let copy: (String) -> Void
    private let open: (URL) -> Void
    private let reveal: (URL) -> Void
    private let reload: () -> Void
    private let quit: () -> Void
    private var ticking = false

    init(
        sources: StatusSources,
        panel: any StatusPanel,
        canShow: @escaping () -> Bool = { NSApp.modalWindow == nil },
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = {
            DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1)
        },
        copy: @escaping (String) -> Void = {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString($0, forType: .string)
        },
        open: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        reveal: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        reload: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.sources = sources
        self.panel = panel
        self.canShow = canShow
        self.schedule = schedule
        self.copy = copy
        self.open = open
        self.reveal = reveal
        self.reload = reload
        self.quit = quit
        panel.perform = { [weak self] in self?.perform($0) }
    }

    func toggle() {
        if panel.isVisible {
            panel.hide()
        } else if canShow() {
            refresh()
            panel.show()
            scheduleTick()
        }
    }

    func perform(_ action: StatusAction) {
        switch action {
        case .openSettings: open(AccessibilityPermission.settingsURL)
        case .revealConfig: reveal(sources.configPath())
        case .createConfig:
            sources.createConfig()
            refresh()
        case .reload:
            reload()
            refresh()
        case .copyDiagnostics: copy(report().text)
        case let .copyFix(requirement): copy(requirement.fixCommand)
        case let .open(url): open(url)
        case .quit: quit()
        }
    }

    private func refresh() {
        panel.render(report())
    }

    private func scheduleTick() {
        guard !ticking else { return }

        ticking = true
        schedule(Self.refreshInterval) { [weak self] in
            guard let self else { return }

            ticking = false
            guard panel.isVisible else { return }

            refresh()
            scheduleTick()
        }
    }

    private func report() -> StatusReport {
        let path = sources.configPath()

        return StatusReport(
            version: sources.version(),
            build: sources.build(),
            system: sources.system(),
            accessibilityGranted: sources.isTrusted(),
            hotkeysListening: sources.hotkeysListening(),
            secureInputHeld: sources.secureInputHeld(),
            workspace: sources.workspace(),
            display: sources.display(),
            configPath: (path.path as NSString).abbreviatingWithTildeInPath,
            configExists: FileManager.default.fileExists(atPath: path.path),
            configError: sources.configError(),
            settings: Requirements.all.map { StatusReport.Setting(requirement: $0, value: $0.value(read: sources.readSetting)) }
        )
    }
}
