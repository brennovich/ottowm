import AppKit

/// The About window: reads the report when shown and again when the app is activated, and runs its buttons.
final class Status {
    private let sources: StatusSources
    private let panel: any StatusPanel
    private let notificationCenter: NotificationCenter
    private let canShow: () -> Bool
    private let isActive: () -> Bool
    private let copy: (String) -> Void
    private let open: (URL) -> Void
    private let reveal: (URL) -> Void
    private let reload: () -> Void
    private var observer: NSObjectProtocol?
    private var skipNextActivation = false

    init(
        sources: StatusSources,
        panel: any StatusPanel,
        notificationCenter: NotificationCenter = .default,
        canShow: @escaping () -> Bool = { NSApp.modalWindow == nil },
        isActive: @escaping () -> Bool = { NSApp.isActive },
        copy: @escaping (String) -> Void = {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString($0, forType: .string)
        },
        open: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        reveal: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        reload: @escaping () -> Void
    ) {
        self.sources = sources
        self.panel = panel
        self.notificationCenter = notificationCenter
        self.canShow = canShow
        self.isActive = isActive
        self.copy = copy
        self.open = open
        self.reveal = reveal
        self.reload = reload
        panel.perform = { [weak self] in self?.perform($0) }
        watchActivation()
    }

    deinit {
        if let observer { notificationCenter.removeObserver(observer) }
    }

    func toggle() {
        if panel.isVisible {
            panel.hide()
        } else if canShow() {
            refresh()
            // Showing the window activates the app, and that activation reads the report just read here.
            skipNextActivation = !isActive()
            panel.show()
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
        case .copyFixes: copy(report().fixes)
        }
    }

    /// Coming back from System Settings activates OttoWM, and a permission granted there shows on the report read here.
    private func watchActivation() {
        observer = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, panel.isVisible else { return }
            guard !skipNextActivation else {
                skipNextActivation = false
                return
            }

            refresh()
        }
    }

    private func refresh() {
        panel.render(report())
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
            display: sources.display(),
            configPath: (path.path as NSString).abbreviatingWithTildeInPath,
            configExists: sources.configExists(path),
            configError: sources.configError(),
            settings: Requirements.all.map { StatusReport.Setting(requirement: $0, value: $0.value(read: sources.readSetting)) }
        )
    }
}
