import AppKit

/// The About panel: the app identity on top, the status grid, the buttons and the links. Draws a `StatusReport`.
final class StatusWindow: NSPanel, StatusPanel {
    var perform: ((StatusAction) -> Void)?

    private static let releasesURL = URL(string: "https://github.com/brennovich/ottowm/releases/latest")!
    private static let readmeURL = URL(string: "https://github.com/brennovich/ottowm#readme")!
    private static let licenseURL = URL(string: "https://github.com/brennovich/ottowm/blob/main/LICENSE")!

    private let versionLabel = NSTextField(labelWithString: "")
    private let systemLabel = NSTextField(labelWithString: "")
    private let accessibility = StateView()
    private let hotkeys = StateView()
    private let secureInput = StateView()
    private let workspaceLabel = NSTextField(labelWithString: "")
    private let configLabel = NSTextField(labelWithString: "")
    private let configErrorLabel = NSTextField(wrappingLabelWithString: "")
    private let revealButton: ActionButton
    private let reloadButton: ActionButton
    private let createButton: ActionButton
    private let settingsButton: ActionButton
    private let settings: [(requirement: Requirement, state: StateView, fix: ActionButton, fixRow: NSView)]
    private var grid: NSGridView?
    /// The widest a value cell gets: a longer setting name wraps, a longer config path truncates.
    fileprivate static let valueWidth: CGFloat = 190
    private var previousApplication: NSRunningApplication?

    init() {
        revealButton = ActionButton(title: "Reveal")
        reloadButton = ActionButton(title: "Reload")
        createButton = ActionButton(title: "Create from defaults")
        settingsButton = ActionButton(title: "Open System Settings")
        settings = Requirements.all.map { requirement in
            let fix = ActionButton(title: "Copy fix")
            return (requirement, StateView(), fix, Self.indented(fix))
        }
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
        workspaceLabel.stringValue = "\(report.workspace) on \(report.display)"
        configLabel.stringValue = report.configExists ? report.configPath : "Bundled defaults"
        configLabel.toolTip = report.configExists ? nil : "No file at \(report.configPath)"
        revealButton.isHidden = !report.configExists
        reloadButton.isHidden = !report.configExists
        createButton.isHidden = report.configExists
        configErrorLabel.stringValue = report.configError.map { "Last reload: \($0)" } ?? ""
        setRow(of: configErrorLabel, hidden: report.configError == nil)
        for (setting, row) in zip(report.settings, settings) {
            row.state.set(healthy: setting.isMet, text: setting.requirement.name)
            setRow(of: row.fixRow, hidden: setting.isMet)
        }
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
        for row in settings {
            row.fix.pressed = { [weak self] in self?.perform?(.copyFix(row.requirement)) }
        }
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
        let buttons = buttons()
        let links = links()

        let stack = NSStackView(views: header + [grid, buttons, links])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(12, after: header[0])
        stack.setCustomSpacing(20, after: header[3])
        stack.setCustomSpacing(20, after: grid)
        stack.setCustomSpacing(16, after: buttons)
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
        workspaceLabel.font = Self.valueFont
        configLabel.font = Self.valueFont
        configLabel.lineBreakMode = .byTruncatingMiddle
        configLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Self.valueWidth).isActive = true
        configErrorLabel.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        configErrorLabel.preferredMaxLayoutWidth = Self.valueWidth

        let grid = NSGridView(views: [
            [Self.label("Accessibility"), accessibility],
            [NSGridCell.emptyContentView, settingsButton],
            [Self.label("Hotkeys"), hotkeys],
            [Self.label("Secure input"), secureInput],
            [Self.label("Workspace"), workspaceLabel],
            [NSGridCell.emptyContentView, Self.spacer()],
            [Self.label("Config"), configLabel],
            [NSGridCell.emptyContentView, Self.row(revealButton, reloadButton, createButton)],
            [NSGridCell.emptyContentView, configErrorLabel],
            [NSGridCell.emptyContentView, Self.spacer()],
        ] + settings.enumerated().flatMap { index, row in
            [
                [Self.label(index == 0 ? "macOS settings" : ""), row.state],
                [NSGridCell.emptyContentView, row.fixRow],
            ]
        })
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 5
        grid.columnSpacing = 8
        self.grid = grid
        return grid
    }

    private func buttons() -> NSStackView {
        let copy = ActionButton(title: "Copy diagnostics")
        copy.pressed = { [weak self] in self?.perform?(.copyDiagnostics) }
        let quit = ActionButton(title: "Quit OttoWM")
        quit.pressed = { [weak self] in self?.perform?(.quit) }
        let buttons = NSStackView(views: [copy, quit])
        buttons.spacing = 12
        return buttons
    }

    private func links() -> NSStackView {
        let links = NSStackView(views: [
            link("Releases", Self.releasesURL),
            Self.label("·"),
            link("README", Self.readmeURL),
            Self.label("·"),
            link("MIT License", Self.licenseURL),
        ])
        links.spacing = 4
        return links
    }

    private func link(_ title: String, _ url: URL) -> NSButton {
        let button = ActionButton(title: title)
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.linkColor,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ])
        button.cursor = .pointingHand
        button.pressed = { [weak self] in self?.perform?(.open(url)) }
        return button
    }

    private static let valueFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        return label
    }

    /// A button under a dotted row, in line with the row's text.
    private static func indented(_ button: NSButton) -> NSStackView {
        let stack = NSStackView(views: [button])
        stack.edgeInsets = NSEdgeInsets(top: 0, left: StateView.textOffset, bottom: 0, right: 0)
        return stack
    }

    private static func row(_ views: NSView...) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.spacing = 8
        stack.alignment = .firstBaseline
        return stack
    }

    private static func spacer() -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: 4).isActive = true
        return view
    }
}

/// A coloured dot and a text: green while healthy, red otherwise. A long text wraps, the dot stays on its first line.
private final class StateView: NSStackView {
    private static let dotSize: CGFloat = 8
    private static let spacing: CGFloat = 6
    /// Where the text starts, from the leading edge.
    static let textOffset = dotSize + spacing

    private let dot = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)
        dot.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
        dot.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Self.dotSize, weight: .regular)
        dot.widthAnchor.constraint(equalToConstant: Self.dotSize).isActive = true
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.preferredMaxLayoutWidth = StatusWindow.valueWidth - Self.textOffset
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
    /// The cursor over the button, when it is not the arrow.
    var cursor: NSCursor? {
        didSet { window?.invalidateCursorRects(for: self) }
    }

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

    override func resetCursorRects() {
        guard let cursor else { return }

        addCursorRect(bounds, cursor: cursor)
    }

    @objc private func fire() {
        pressed?()
    }
}
