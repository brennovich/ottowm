import AppKit

/// The About panel: the app identity on top, the status grid and the buttons. Draws a `StatusReport`.
final class StatusWindow: NSPanel, StatusPanel {
    var perform: ((StatusAction) -> Void)?

    private let versionLabel = NSTextField(labelWithString: "")
    private let systemLabel = NSTextField(labelWithString: "")
    private let accessibility = StateView()
    private let hotkeys = StateView()
    private let secureInput = StateView()
    private let displayLabel = NSTextField(labelWithString: "")
    private let configLabel = NSTextField(labelWithString: "")
    private let configErrorLabel = NSTextField(wrappingLabelWithString: "")
    private let revealButton = ActionButton(title: "Reveal")
    private let reloadButton = ActionButton(title: "Reload")
    private let createButton = ActionButton(title: "Create from defaults")
    private let settingsButton = ActionButton(title: "Open System Settings")
    private let fixesButton = ActionButton(title: "Copy fixes")
    private let diagnosticsButton = ActionButton(title: "Copy diagnostics")
    private let settings = Requirements.all.map { _ in StateView() }
    private var grid: NSGridView?
    /// The widest a value cell gets: a longer setting name wraps, a longer config path truncates.
    fileprivate static let valueWidth: CGFloat = 165
    private var previousApplication: NSRunningApplication?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // A panel hides when its application deactivates; this one stays until it is closed.
        hidesOnDeactivate = false
        // The panel is kept and shown again.
        isReleasedWhenClosed = false
        wire()
        contentView = layout()
    }

    // MARK: StatusPanel

    func render(_ report: StatusReport) {
        versionLabel.stringValue = "\(report.version) (\(report.build))"
        systemLabel.stringValue = report.system
        accessibility.set(healthy: report.accessibilityGranted, text: report.accessibilityGranted ? "Granted" : "Not granted")
        hotkeys.set(healthy: report.hotkeysListening, text: report.hotkeysListening ? "Listening" : "Not listening")
        secureInput.set(healthy: !report.secureInputHeld, text: report.secureInputHeld ? "Held by another app" : "Free")
        setRow(of: settingsButton, hidden: report.accessibilityGranted)
        displayLabel.stringValue = report.display
        configLabel.stringValue = report.configExists ? report.configPath : "Bundled defaults"
        configLabel.toolTip = report.configExists ? nil : "No file at \(report.configPath)"
        revealButton.isHidden = !report.configExists
        reloadButton.isHidden = !report.configExists
        createButton.isHidden = report.configExists
        configErrorLabel.stringValue = report.configError.map { "Last reload: \($0)" } ?? ""
        setRow(of: configErrorLabel, hidden: report.configError == nil)
        for (setting, state) in zip(report.settings, settings) {
            state.set(healthy: setting.isMet, text: setting.requirement.name)
        }
        setRow(of: fixesButton, hidden: report.fixes.isEmpty)
        fit()
    }

    func show() {
        let current = NSRunningApplication.current
        previousApplication = NSWorkspace.shared.frontmostApplication.flatMap { $0 == current ? nil : $0 }
        center()
        makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func hide() {
        close()
    }

    // MARK: NSPanel

    /// Esc. Neither NSWindow nor NSPanel closes on it, and an accessory app has no menu for Cmd-W.
    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }

    /// Once the panel is gone no application is active, so the one that was is brought back. Not when the user
    /// already switched to another application: OttoWM is inactive then, and that application keeps the focus.
    override func close() {
        let restore = NSApp.isActive
        super.close()
        if restore { previousApplication?.activate(options: []) }
        previousApplication = nil
    }

    // MARK: Layout

    private func wire() {
        settingsButton.pressed = { [weak self] in self?.perform?(.openSettings) }
        revealButton.pressed = { [weak self] in self?.perform?(.revealConfig) }
        reloadButton.pressed = { [weak self] in self?.perform?(.reload) }
        createButton.pressed = { [weak self] in self?.perform?(.createConfig) }
        fixesButton.pressed = { [weak self] in self?.perform?(.copyFixes) }
        diagnosticsButton.pressed = { [weak self] in self?.perform?(.copyDiagnostics) }
    }

    /// A hidden view keeps its grid row's height, so the row is hidden with it.
    private func setRow(of view: NSView, hidden: Bool) {
        grid?.cell(for: view)?.row?.isHidden = hidden
    }

    private func fit() {
        guard let contentView else { return }

        contentView.layoutSubtreeIfNeeded()
        setContentSize(contentView.fittingSize)
    }

    private func layout() -> NSView {
        let header = header()
        let grid = statusGrid()

        let stack = NSStackView(views: header + [grid])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(12, after: header[0])
        stack.setCustomSpacing(20, after: header[3])
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 24, bottom: 24, right: 24)

        // The centering constraints of a stack let a wide row overflow it; these make the stack as wide as its widest row.
        NSLayoutConstraint.activate(stack.views.flatMap { view in
            [
                view.leadingAnchor.constraint(greaterThanOrEqualTo: stack.leadingAnchor, constant: stack.edgeInsets.left),
                view.trailingAnchor.constraint(lessThanOrEqualTo: stack.trailingAnchor, constant: -stack.edgeInsets.right),
            ]
        })
        return stack
    }

    /// The icon, the name, the version and the macOS line.
    private func header() -> [NSView] {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let name = NSTextField(labelWithString: "OttoWM")
        name.font = .systemFont(ofSize: 22, weight: .bold)
        versionLabel.textColor = .secondaryLabelColor
        systemLabel.textColor = .secondaryLabelColor
        systemLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        return [icon, name, versionLabel, systemLabel]
    }

    private func statusGrid() -> NSGridView {
        displayLabel.font = Self.valueFont
        displayLabel.textColor = .secondaryLabelColor
        configLabel.font = Self.valueFont
        configLabel.textColor = .secondaryLabelColor
        configLabel.lineBreakMode = .byTruncatingMiddle
        configLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Self.valueWidth).isActive = true
        configErrorLabel.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        configErrorLabel.preferredMaxLayoutWidth = Self.valueWidth

        let grid = NSGridView(views: [
            [Self.label("Accessibility"), accessibility],
            [NSGridCell.emptyContentView, settingsButton],
            [Self.label("Hotkeys"), hotkeys],
            [Self.label("Secure input"), secureInput],
            [Self.label("Display"), displayLabel],
            [Self.label("Config"), configLabel],
            [NSGridCell.emptyContentView, Self.row(revealButton, reloadButton, createButton)],
            [NSGridCell.emptyContentView, configErrorLabel],
        ] + settings.enumerated().map { index, state in
            [Self.label(index == 0 ? "macOS" : ""), state]
        } + [
            [NSGridCell.emptyContentView, fixesButton],
            [NSGridCell.emptyContentView, diagnosticsButton],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 5
        grid.columnSpacing = 8
        // The config and the macOS settings are blocks of their own; a hidden row drops its padding with it, so the
        // gap is set on rows that are always up.
        grid.cell(for: displayLabel)?.row?.bottomPadding = 10
        if let first = settings.first {
            grid.cell(for: first)?.row?.topPadding = 10
        }
        self.grid = grid
        return grid
    }

    private static let valueFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Self.valueFont
        return label
    }

    private static func row(_ views: NSView...) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.spacing = 8
        stack.alignment = .firstBaseline
        return stack
    }
}

/// A coloured dot and a text: green while healthy, red otherwise. A long text wraps, the dot stays on its first line.
private final class StateView: NSStackView {
    private static let dotSize: CGFloat = 8
    private static let spacing: CGFloat = 6

    private let dot = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)
        dot.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
        dot.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Self.dotSize, weight: .regular)
        dot.widthAnchor.constraint(equalToConstant: Self.dotSize).isActive = true
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = StatusWindow.valueWidth - Self.dotSize - Self.spacing
        addView(dot, in: .leading)
        addView(label, in: .leading)
        spacing = Self.spacing
        alignment = .firstBaseline
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(healthy: Bool, text: String) {
        dot.contentTintColor = healthy ? .systemGreen : .systemRed
        label.stringValue = text
    }
}

/// A push button running a closure, so the window needs no selector per button.
private final class ActionButton: NSButton {
    var pressed: (() -> Void)?

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        controlSize = .small
        font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        target = self
        action = #selector(fire)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func fire() {
        pressed?()
    }
}
