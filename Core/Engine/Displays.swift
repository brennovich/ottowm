import CoreGraphics

/// The displays connected at launch, each with the engine of its native Space. Each engine sees
/// only the windows on its display, and each binding and window event goes to one engine.
final class Displays {
    private typealias Member = (display: Display, workspaces: Workspaces, engine: Engine)

    private let arrangement: Arrangement
    private let windowSystem: WindowSystem
    private let active: () -> DisplayID?
    private let write: ([SavedState]) -> Void
    private var members: [Member] = []
    private var sections: [DisplayID: SavedState] = [:]

    /// - Parameter engine: builds the workspaces and the engine of a display from the window
    ///   system scoped to it and the closure that saves its state.
    init(
        screens: Screens,
        windowSystem: WindowSystem,
        write: @escaping ([SavedState]) -> Void,
        engine: (Display, WindowSystem, @escaping (SavedState) -> Void) -> (workspaces: Workspaces, engine: Engine)
    ) {
        let connected = screens.all()
        arrangement = Arrangement(displays: connected.isEmpty ? [.unknown] : connected)
        self.windowSystem = windowSystem
        active = screens.active
        self.write = write

        members = arrangement.displays.map { display in
            let scoped = windowSystem.scoped { [arrangement] in arrangement.display(of: $0)?.id == display.id }
            let built = engine(display, scoped) { [weak self] in self?.save($0, of: display.id) }
            return (display, built.workspaces, built.engine)
        }
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
            engine(on: focusedDisplay?.id ?? active()).handle(action)
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

    func resync(windows: [WindowSnapshot]) {
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
