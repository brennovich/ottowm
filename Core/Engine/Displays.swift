import CoreGraphics

/// The connected displays, each with the engine of its native Space. Each engine sees only the
/// windows on its display, and each binding and window event goes to one engine.
final class Displays {
    typealias Parts = (workspaces: Workspaces, desktop: any Desktop, engine: Engine)
    private typealias Member = (display: Display, workspaces: Workspaces, desktop: any Desktop, engine: Engine)

    private var arrangement: Arrangement
    private let screens: Screens
    private let windowSystem: WindowSystem
    private let screenIsLocked: () -> Bool
    private let write: ([SavedState]) -> Void
    private let makeEngine: (Display, WindowSystem, @escaping (SavedState) -> Void) -> Parts
    private var members: [Member] = []
    private var sections: [DisplayID: SavedState] = [:]

    /// - Parameter engine: builds the workspaces, the desktop and the engine of a display from the
    ///   window system scoped to it and the closure that saves its state. It is called once per
    ///   display during the init, the primary display first, and once per display added later.
    init(
        screens: Screens,
        windowSystem: WindowSystem,
        screenIsLocked: @escaping () -> Bool,
        write: @escaping ([SavedState]) -> Void,
        engine: @escaping (Display, WindowSystem, @escaping (SavedState) -> Void) -> Parts
    ) {
        let connected = screens.all()
        arrangement = Arrangement(displays: connected.isEmpty ? [.unknown] : connected)
        self.screens = screens
        self.windowSystem = windowSystem
        self.screenIsLocked = screenIsLocked
        self.write = write
        makeEngine = engine

        members = arrangement.displays.map(member(on:))
        screens.startWatching { [weak self] in self?.screenParametersChanged() }
    }

    func start(windows: [WindowSnapshot], restoring saved: [SavedState]?) {
        let windowsByDisplay = windowsByDisplay(windows)
        for member in members {
            let section = saved?.first { $0.display.id == member.display.id }
            member.engine.start(windows: windowsByDisplay[member.display.id] ?? [], restoring: section)
        }
    }

    /// The active display is the display of the focused window, which is where keystrokes go.
    /// With no window focused, as after a click on a display's desktop, it is the display with
    /// the menu bar. The action runs in the same operation, so the engine's read of the focused
    /// window returns the value read here.
    func handle(_ action: Action) {
        windowSystem.duringOperation("route-action") {
            let focusedDisplay = windowSystem.focused().flatMap { arrangement.display(of: $0.frame) }
            engine(on: focusedDisplay?.id ?? screens.active()).handle(action)
        }
    }

    /// An event without a snapshot has no frame to route by. Every engine gets it, and an
    /// engine that does not hold the window does nothing with it.
    func handle(_ event: WindowEvent) {
        switch event {
        case let .created(win), let .unminimized(win):
            engine(holding: win.frame).handle(event)
        case let .focused(win):
            let holder = members.first { $0.workspaces.membership(of: win.id) != .unassigned }
            (holder?.engine ?? engine(holding: win.frame)).handle(event)
        case .destroyed, .minimized, .reframed:
            for member in members { member.engine.handle(event) }
        }
    }

    /// Runs at the unlock, after the displays added or removed behind the lock screen are followed.
    func resync(windows: [WindowSnapshot]) {
        followArrangement()

        let windowsByDisplay = windowsByDisplay(windows)
        for member in members {
            member.engine.resync(windows: windowsByDisplay[member.display.id] ?? [])
        }
    }

    func saveState() {
        for member in members { member.engine.saveState() }
    }

    func stop() {
        for member in members { member.engine.stop() }
    }

    /// The notification also follows a Dock or menu bar change, and macOS posts it more than
    /// once per plug. Absorbing an engine moves windows through AX, which fails behind the lock
    /// screen, so the displays added or removed are followed at the unlock.
    private func screenParametersChanged() {
        let connected = screens.all()
        guard !connected.isEmpty else { return }

        let displays = connected.map { "\($0.id.rawValue) \($0.fullFrame)" }.joined(separator: ", ")
        Log.desktop.debug("screen parameters changed, displays: \(displays)")
        arrangement = Arrangement(displays: connected)
        for member in members {
            guard let display = connected.first(where: { $0.id == member.display.id }) else { continue }
            member.desktop.change(to: display)
        }
        guard !screenIsLocked() else { return }

        followArrangement()
    }

    /// An added display gets its engine before the removed ones are absorbed, so the primary
    /// display has one. `members` follows the arrangement's order, the primary first.
    private func followArrangement() {
        let removed = members.filter { member in !arrangement.displays.contains { $0.id == member.display.id } }
        members = arrangement.displays.map { display in
            members.first { $0.display.id == display.id } ?? startedMember(on: display)
        }
        for member in removed { absorb(member, into: members[0]) }
    }

    /// A display that returns gets a new engine, without the workspaces it had.
    private func startedMember(on display: Display) -> Member {
        Log.desktop.info("display added: \(display.logDescription)")
        let member = member(on: display)
        member.engine.start(windows: [], restoring: nil)
        return member
    }

    /// The removed engine is not stopped: stopping puts its parked windows back on screen.
    private func absorb(_ removed: Member, into primary: Member) {
        Log.desktop.info("display removed: \(removed.display.id.rawValue), absorbed by \(primary.display.id.rawValue)")
        removed.engine.saveState()
        if let state = sections.removeValue(forKey: removed.display.id) {
            primary.engine.absorb(state)
        }
        primary.engine.saveState()
        write(members.compactMap { sections[$0.display.id] })
    }

    private func member(on display: Display) -> Member {
        let scoped = windowSystem.scoped { [weak self] in self?.arrangement.display(of: $0)?.id == display.id }
        let built = makeEngine(display, scoped) { [weak self] in self?.save($0, of: display.id) }
        return (display, built.workspaces, built.desktop, built.engine)
    }

    private func engine(on displayId: DisplayID?) -> Engine {
        (members.first { $0.display.id == displayId } ?? members[0]).engine
    }

    private func engine(holding frame: CGRect) -> Engine {
        engine(on: arrangement.display(of: frame)?.id)
    }

    private func windowsByDisplay(_ windows: [WindowSnapshot]) -> [DisplayID?: [WindowSnapshot]] {
        Dictionary(grouping: windows) { arrangement.display(of: $0.frame)?.id }
    }

    private func save(_ state: SavedState, of displayId: DisplayID) {
        sections[displayId] = state
        write(members.compactMap { sections[$0.display.id] })
    }
}
