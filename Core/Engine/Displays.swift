import CoreGraphics

/// The connected displays, each with the engine of its native Space. Each engine sees only the
/// windows on its display, and each binding and window event goes to one engine.
final class Displays {
    private var arrangement: Arrangement
    private let screens: Screens
    private let windowSystem: WindowSystem
    private let layouts: DisplayLayouts
    private let screenIsLocked: () -> Bool
    private let write: (SavedSession) -> Void
    private let removed: (DisplayID) -> Void
    private let makeEngine: (Display, WindowSystem) -> Engine
    private var engines: [Engine] = []
    private var lastWritten: SavedSession?

    /// - Parameter engine: builds the engine of a display from the window system scoped to it.
    ///   It is called once per display during the init, the primary display first, and once per
    ///   display added later.
    /// - Parameter removed: called with each removed display, once its engine is absorbed.
    init(
        screens: Screens,
        windowSystem: WindowSystem,
        layouts: DisplayLayouts,
        screenIsLocked: @escaping () -> Bool,
        write: @escaping (SavedSession) -> Void,
        removed: @escaping (DisplayID) -> Void,
        engine: @escaping (Display, WindowSystem) -> Engine
    ) {
        let connected = screens.all()
        arrangement = Arrangement(displays: connected.isEmpty ? [.unknown] : connected)
        self.screens = screens
        self.windowSystem = windowSystem
        self.layouts = layouts
        self.screenIsLocked = screenIsLocked
        self.write = write
        self.removed = removed
        makeEngine = engine

        engines = arrangement.displays.map(engine(on:))
        screens.startWatching { [weak self] in self?.screenParametersChanged() }
    }

    /// A saved layout of a window that is gone is left out.
    func start(windows: [WindowSnapshot], restoring saved: SavedSession?) {
        if let saved {
            let found = Set(windows.map(\.id))
            layouts.load(saved.layouts.mapValues { $0.filter { found.contains($0.key) } })
        }
        let windowsByOwner = windowsByOwner(windows)
        for engine in engines {
            let section = saved?.displays.first { $0.display.id == engine.display.id }
            engine.start(windows: windowsByOwner[engine.display.id] ?? [], restoring: section)
        }
    }

    /// The active display is the display of the focused window, which is where keystrokes go.
    /// With no window focused, as after a click on a display's desktop, it is the display with
    /// the menu bar. The action runs in the same operation, so the engine's read of the focused
    /// window returns the value read here.
    func handle(_ action: Action) {
        windowSystem.duringOperation("route-action") {
            reconcile()
            let focusedDisplay = windowSystem.focused().flatMap { arrangement.display(of: $0.frame) }
            engine(on: focusedDisplay?.id ?? screens.active()).handle(action)
        }
    }

    /// An event without a snapshot has no frame to route by, so only the engine holding the
    /// window gets it. The accessibility reads fail behind the lock screen, so the events that
    /// change a workspace are dropped there; `reframed` only reparks a parked window.
    func handle(_ event: WindowEvent) {
        switch event {
        case let .reframed(windowId?):
            engines.first { $0.holds(windowId) }?.handle(event)
        case .reframed(nil):
            break
        case _ where screenIsLocked():
            Log.engine.debug("window event ignored: the screen is locked")
        case let .created(win), let .unminimized(win), let .focused(win):
            windowSystem.duringOperation("route-event") {
                reconcile()
                owner(of: win.id, frame: win.frame).handle(event)
            }
        case let .destroyed(windowId):
            guard let engine = engines.first(where: { $0.holds(windowId) }) else { return layouts.forget(windowId) }
            engine.handle(event)
        case let .minimized(windowId):
            engines.first { $0.holds(windowId) }?.handle(event)
        }
    }

    /// Runs at the unlock, after the screen changes behind the lock screen are followed.
    func resync(windows: [WindowSnapshot]) {
        followScreens()
        windowSystem.duringOperation("reconcile") { reconcile() }

        let windowsByOwner = windowsByOwner(windows)
        for engine in engines {
            engine.resync(windows: windowsByOwner[engine.display.id] ?? [])
        }
    }

    /// Writes nothing when the session is the one written last.
    func saveState() {
        let session = SavedSession(displays: engines.map(\.savedState), layouts: layouts.all)
        guard session != lastWritten else { return }
        lastWritten = session
        write(session)
    }

    /// Saved with every window back on screen, the way the next launch finds them.
    func stop() {
        for engine in engines { engine.stop() }
        saveState()
    }

    /// The notification also follows a Dock or menu bar change, and macOS posts it more than
    /// once per plug. The accessibility reads fail behind the lock screen, and a window that
    /// cannot be read would be recorded as parked, so a change behind it is followed at the unlock.
    private func screenParametersChanged() {
        guard !screenIsLocked() else { return }

        followScreens()
    }

    private func followScreens() {
        let connected = screens.all()
        guard !connected.isEmpty else { return }

        let displays = connected.map { "\($0.id.rawValue) \($0.fullFrame)" }.joined(separator: ", ")
        Log.desktop.debug("screen parameters changed, displays: \(displays)")
        arrangement = Arrangement(displays: connected)
        for engine in engines {
            guard let display = arrangement.displays.first(where: { $0.id == engine.display.id }) else { continue }
            engine.change(to: display)
        }
        followArrangement()
    }

    /// An added display gets its engine before the removed ones are absorbed, so the primary
    /// display has one. `engines` follows the arrangement's order, the primary first.
    private func followArrangement() {
        let removed = engines.filter { engine in !arrangement.displays.contains { $0.id == engine.display.id } }
        engines = arrangement.displays.map { display in
            engine(of: display.id) ?? startedEngine(on: display)
        }
        for engine in removed {
            absorb(engine, into: engines[0])
            self.removed(engine.display.id)
        }
    }

    /// A display that returns gets a new engine, without the workspaces it had.
    private func startedEngine(on display: Display) -> Engine {
        Log.desktop.notice("display added: \(display.logDescription)")
        let engine = engine(on: display)
        engine.start(windows: [], restoring: nil)
        return engine
    }

    /// The removed engine is not stopped: stopping puts its parked windows back on screen.
    private func absorb(_ removed: Engine, into primary: Engine) {
        Log.desktop.notice("display removed: \(removed.display.id.rawValue), absorbed by \(primary.display.id.rawValue)")
        primary.absorb(removed.savedState)
        saveState()
    }

    /// A drag to another display reaches OttoWM only as `reframed`, so a window can stand on
    /// one display while the engine of another holds it. A parked window stands at its own
    /// display's corner, and a window not on screen is left to the engine that holds it. A
    /// window the engine there refuses, as when another native Space is in front on that
    /// display, stays with the engine that holds it.
    private func reconcile() {
        guard engines.count > 1 else { return }

        for engine in engines {
            let frames = windowSystem.frames(of: Array(engine.activeWindowIds))
            for (windowId, frame) in frames.sorted(by: { $0.key < $1.key }) {
                guard let displayId = arrangement.display(of: frame)?.id, displayId != engine.display.id,
                      let target = self.engine(of: displayId),
                      let win = windowSystem.snapshot(of: windowId)
                else { continue }

                guard target.assign(win) else { continue }

                engine.release(windowId)
            }
        }
    }

    private func engine(on display: Display) -> Engine {
        let scoped = windowSystem.scoped { [weak self] in self?.arrangement.display(of: $0)?.id == display.id }
        return makeEngine(display, scoped)
    }

    private func engine(of displayId: DisplayID) -> Engine? {
        engines.first { $0.display.id == displayId }
    }

    private func engine(on displayId: DisplayID?) -> Engine {
        displayId.flatMap(engine(of:)) ?? engines[0]
    }

    /// The engine holding the window, parked or full screen, else the display holding the frame.
    private func owner(of windowId: CGWindowID, frame: CGRect) -> Engine {
        engines.first { $0.holds(windowId) } ?? engine(on: arrangement.display(of: frame)?.id)
    }

    private func windowsByOwner(_ windows: [WindowSnapshot]) -> [DisplayID: [WindowSnapshot]] {
        Dictionary(grouping: windows) { owner(of: $0.id, frame: $0.frame).display.id }
    }
}
