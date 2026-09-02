# Architecture

OttoWM is a headless agent that offers several workspaces on one native macOS Space.

## Vocabulary

| Concept        | Meaning                                                                                                       |
|----------------|---------------------------------------------------------------------------------------------------------------|
| Native Space   | A macOS space. OttoWM uses only the one it starts on. A window on another Space is ignored.                   |
| Desktop        | The native Space OttoWM controls, and the component that moves windows on it.                                 |
| Workspace      | A numbered set of windows. It exists as soon as an action names it.                                           |
| Managed window | A window that belongs to a workspace.                                                                         |
| Placement      | Where a managed window sits: `active` on screen, or `parked` at the hidden edge.                              |
| Hidden edge    | The bottom-right corner of the display. A parked window sits there.                                           |
| Tab group      | The windows macOS shows as tabs of one window. See [Tabbed windows](#tabbed-windows).                         |
| Window id      | The `CGWindowID` of a window. It identifies the window for as long as the window lives.                       |
| Frame          | A rect in top-left coordinates.                                                                               |
| Operation      | One unit of engine work. The focused window and the list of on-screen window ids are read at most once in it. |

## Key types

```
WindowEvent  = created(WindowSnapshot) | focused(WindowSnapshot) | destroyed(id) | minimized(id) | unminimized(WindowSnapshot)
Action       = switchToWorkspace(n) | moveWindowToWorkspace(n) | focus(direction) | moveWindow(step) | quit | restart
Direction    = north | east | south | west                       // "focus east" in the config
Step         = (direction, points)                               // "move-window east 15" in the config
KeyCombo     = (keyCode, [ModifierKey: ModifierSide])            // "lopt-shift-1"
Placement    = active | parked
WindowSnapshot(id, appName, isStandard, hasCloseButton, hasMinimizeButton, isFullScreen, isMinimized, frame)
```

## Level 1 — Context

```mermaid
flowchart LR
    user([User])
    config[(Config file)]
    otto["OttoWM"]
    macos["macOS"]

    user -->|key combos| otto
    user -->|Cmd-Tab, Dock, Mission Control| macos
    config -->|bindings| otto
    otto -->|moves and focuses windows| macos
    macos -->|window events| otto
```

## Level 2 — Subsystems

```mermaid
flowchart LR
    Input -->|Action| Engine
    Engine -->|restart| Input
    macOS["macOS boundary"] -->|WindowEvent| Engine
    Engine -->|place, focus, read| macOS
    Engine -->|assign, switch| Model
    Lifecycle -->|start, stop, screen lock| Engine
```

## Level 3 — Components

| Component                   | Category  | Description                                                                             |
|-----------------------------|-----------|-----------------------------------------------------------------------------------------|
| `ConfigFile`                | Input     | Reads the user's config file, or the bundled one.                                       |
| `Config`                    | Input     | The `KeyCombo → Action` table, indexed by key code.                                     |
| `Bindings`                  | Input     | The bindings currently up: `start`, `stop`, `reload`.                                   |
| `Hotkeys`                   | Input     | A session `CGEventTap` on keyDown, running on a thread of its own.                      |
| `Engine`                    | Engine    | Turns window events and actions into model updates and window moves.                    |
| `Workspaces`                | Model     | Window → workspace, focus history, current workspace.                                   |
| `Workspace`                 | Model     | The windows of one workspace and the order they were focused in.                        |
| `TabGroups`                 | Model     | Infers which windows are tabs of one another. Reads a window's tab count on demand.     |
| `Neighbors`                 | Model     | The windows around one frame, and which of them a focus move lands on.                  |
| `Step`                      | Model     | One move of a window in points, and where it lands within the screen.                   |
| `AwaitedFocus`              | Model     | The focus requests `Engine` made and has not seen answered.                             |
| `WorkspaceBeforeFullScreen` | Model     | The workspace each full screen window returns to.                                       |
| `ParkedWindows`             | Model     | The windows parked at the hidden edge, and the frame each one is owed back.             |
| `Desktop`                   | macOS     | Parks a window at the hidden edge, restores the frame it is owed, and steps it around.  |
| `HiddenEdge`                | macOS     | The corner sliver a parked window sits in, and the frame one is recovered to.           |
| `WindowSystem`              | macOS     | The focused window, the on-screen window frames, and the tab count of a window.         |
| `AXWindowObserver`          | macOS     | Which applications count, and the `NSWorkspace` notifications of their lifecycle.       |
| `AXWindowEvents`            | macOS     | The AX notifications of the watched applications, as `WindowEvent`s.                    |
| `Applications`              | macOS     | The applications watched, and the window each `CGWindowID` belongs to.                  |
| `Application`               | macOS     | One watched application: its windows and their ids, its channel, and its subscription.  |
| `Subscription`              | macOS     | The AX notifications one element is subscribed to, and whether the attempt succeeded.   |
| `AXNotifications`           | macOS     | The AX notification channel of one process: subscribe an element, invalidate the lot.   |
| `Window`                    | macOS     | The window operations the placement layer needs: snapshot, frames, moves, focus, tabs.  |
| `AXWindow`                  | macOS     | One window: snapshot, frame writes, focus, tab count.                                   |
| `MainScreen`                | macOS     | The geometry of the main display, in top-left coordinates.                              |
| `OperationCache`            | macOS     | Holds one AX or CG read for the length of an operation.                                 |
| `RoundTrips`                | macOS     | Prices an operation in the calls it makes out of the process: how many, of what, cost.  |
| `Signposts`                 | macOS     | The operation and round-trip intervals Instruments records.                             |
| `AppDelegate`               | Lifecycle | The startup order.                                                                      |
| `AccessibilityPermission`   | Lifecycle | The startup gate, and the watch on the accessibility trust.                             |
| `ScreenLock`                | Lifecycle | Reports whether the login window covers the session, and when it is uncovered.          |
| `Lifecycle`                 | Lifecycle | The transitions once it owns windows: `quit`, SIGTERM, relaunch, resync on unlock.      |
| `AccessibilityAlert`        | UI        | The accessibility permission alerts: what they say and how they show.                   |

`Window` is a protocol; `AXWindow` is the implementation the app runs.

`Desktop` is a protocol; `OffscreenParkingDesktop` is the implementation the app runs. It holds no state of its own: `Engine` hands it the frame each window is owed, and records what the placement reports back in `ParkedWindows`, which it reads to tell an active window from a parked one.

### Input

```mermaid
flowchart LR
    ConfigFile -->|Config| Bindings
    Bindings -->|"(keyCode, flags) → Action?"| Hotkeys
    Hotkeys -->|Action| Engine
    Engine -->|restart| Bindings
```

The tap thread matches the key and dispatches the action to the main queue, the only thread the accessibility writes are allowed on.

### Engine and model

```mermaid
flowchart LR
    Engine --> Workspaces
    Engine --> Neighbors
    Engine --> AwaitedFocus
    Engine --> WorkspaceBeforeFullScreen
    Engine --> ParkedWindows
    Workspaces --> Workspace
    Workspaces --> TabGroups
```

Every window event, and every action that touches windows, runs inside `WindowSystem.duringOperation`. Events are dropped while the screen is locked, where every window reads as closed.

### macOS boundary

```mermaid
flowchart TB
    Engine -->|recover, place, focus| Desktop
    Engine -->|focused, shows, frames| WindowSystem
    TabGroups -->|tabCount| WindowSystem
    AXWindowObserver -->|WindowEvent| Engine
    Desktop --> MainScreen
    Desktop --> HiddenEdge
    Desktop --> Applications
    WindowSystem -->|attach the focused window| Applications
    AXWindowObserver -->|start, reconcile, stop| AXWindowEvents
    AXWindowEvents -->|WindowEvent| AXWindowObserver
    AXWindowEvents -->|add, remove| Applications
    Applications --> Application
    Application --> Subscription
    Application --> AXNotifications
    Subscription --> AXNotifications
    AXWindowEvents --> AXWindow
```

### Lifecycle

```mermaid
flowchart LR
    AppDelegate --> AccessibilityPermission
    AccessibilityPermission --> AccessibilityAlert
    AppDelegate --> Engine
    AppDelegate --> Bindings
    AccessibilityPermission -->|trust lost, regained| Bindings
    AppDelegate --> Lifecycle
    Lifecycle --> ScreenLock
    Lifecycle -->|stop, resync| Engine
    Lifecycle -->|screenIsLocked| Engine
    Lifecycle -->|screenIsLocked| AXWindowEvents
    Lifecycle -->|resync| AXWindowObserver
    AccessibilityPermission -->|relaunch| Lifecycle
```

## Flows

### Startup

```mermaid
sequenceDiagram
    AppDelegate->>ConfigFile: load()
    ConfigFile-->>AppDelegate: Config, or ConfigError and exit
    AppDelegate->>AccessibilityPermission: request()
    AccessibilityPermission-->>AppDelegate: granted, quit, or relaunch after the grant
    AppDelegate->>AXWindowObserver: start(handler)
    AXWindowObserver-->>AppDelegate: the windows found while subscribing
    AppDelegate->>Engine: start(windows:)
    Engine->>Desktop: recover(windows)
    Desktop-->>Engine: the same windows, parked ones back on screen
    Engine->>Workspaces: assign each one to workspace 1
    Engine->>Desktop: startWatching(nativeSpaceChange:)
    AppDelegate->>Bindings: start()
```

### Workspace switch

```mermaid
sequenceDiagram
    Hotkeys->>Engine: handle(switchToWorkspace(n))
    Engine->>WindowSystem: focused(), shows(), showsAny()
    Note over Engine: drops the focused window if full screen,<br/>drops the windows that left the desktop,<br/>admits the focused window
    Engine->>Workspaces: switchTo(n, leavingFocusOn: focused)
    Workspaces-->>Engine: (activating, parking)
    Engine->>Desktop: place(each window, at its placement, owing the frame recorded for it)
    Desktop-->>Engine: parked owing a frame, activated, or gone, per window
    Engine->>ParkedWindows: record(what came back)
    alt the desktop is in front
        Engine->>Desktop: focus(nextWindowToFocus)
    else another native Space is in front
        Engine->>Desktop: focus any managed window
    end
```

A window `Desktop.place` cannot reach is no longer managed (maybe moved to another native space).

### Move window to workspace

```mermaid
sequenceDiagram
    Hotkeys->>Engine: handle(moveWindowToWorkspace(n))
    Engine->>WindowSystem: focused()
    WindowSystem-->>Engine: the window, or nothing to move
    Engine->>Desktop: place(id, at: .active if n is current, else .parked)
    Engine->>ParkedWindows: record(what came back)
    Engine->>Workspaces: move(id, to: n)
    Engine->>WorkspaceBeforeFullScreen: forget(id)
    Note over Engine: skipped when a window of the current workspace already has the focus
    Engine->>Desktop: focus(nextWindowToFocus)
```

### Focus a neighbour window

```mermaid
sequenceDiagram
    Hotkeys->>Engine: handle(focus(direction))
    Engine->>WindowSystem: focused()
    Note over Engine: dropped unless that window is in the current workspace
    Engine->>Workspaces: windowIds(in: the current workspace)
    Engine->>ParkedWindows: placement(of: id)
    Engine->>WindowSystem: frames(of: the windows placed active)
    Note over Engine: keeps the on-screen windows that are placed active
    Engine->>Neighbors: nearest(to: direction)
    Neighbors-->>Engine: the window that way, or nothing
    Engine->>Desktop: focus(id)
```

Selects the nearest window (from the active workspace) in the direction pressed, or does nothing if there is none.

### Manual navigation

The user can reach a parked window without OttoWM, through Cmd-Tab, the Dock or Mission Control.

```mermaid
sequenceDiagram
    participant AXWindowObserver
    participant Desktop
    participant Engine
    participant WindowSystem
    participant Workspaces

    alt on the same native Space
        AXWindowObserver->>Engine: focused(a parked window)
        Engine->>WindowSystem: focused()
        Note over Engine: dropped unless the OS reports that window focused now,<br/>and the event is not the answer to a focus OttoWM requested
    else from another native Space
        Desktop->>Engine: nativeSpaceChange()
        Engine->>WindowSystem: focused()
        Note over Engine: followed only when that window is parked
    end
    Note over Engine: dropped by the one-shot ignore flag,<br/>or when every window of the current workspace is already gone
    Engine->>Workspaces: switchTo(that window's workspace)
    Engine->>Desktop: place(id, at: .active) and place(id, at: .parked)
```

A Space change also pulls a parked window back on screen when its full screen instance exits. With no parked window focused, `Engine` answers the change with `repark`, which puts the parked windows found on screen back at the hidden edge.

### Full screen round trip

```mermaid
sequenceDiagram
    Note over Engine: a switch finds the focused window full screen
    Engine->>Workspaces: remove(id)
    Engine->>WorkspaceBeforeFullScreen: record(id, in: the workspace it was in)
    Note over Engine: the window leaves full screen
    AXWindowObserver->>Engine: focused(window)
    Engine->>WorkspaceBeforeFullScreen: workspace(of: id)
    WorkspaceBeforeFullScreen-->>Engine: the recorded workspace
    Engine->>Workspaces: switchTo(it), then assign(window) there
```

The record is taken after the removal, which clears every other trace of the window. A `move-window-to-workspace` on that window clears the record.

### Config reload

```mermaid
sequenceDiagram
    Hotkeys->>Engine: handle(restart)
    Engine->>Bindings: reload()
    Bindings->>ConfigFile: load()
    ConfigFile-->>Bindings: Config, or the bindings already up stay
    Bindings->>Hotkeys: stop()
    Bindings->>Hotkeys: start() a new tap over the new Config
```

The matcher is read on the tap thread, so it is replaced with the tap rather than written under it. The engine, the workspaces and the parked windows are untouched.

### Shutdown

An `LSUIElement` agent has no quit command, so the ways out are a bound `quit` action and a signal. `Lifecycle.relaunch` is the third: it restores the frames the same way, then exits once the new instance is up.

```mermaid
sequenceDiagram
    alt quit action
        Hotkeys->>Engine: handle(quit)
        Engine->>Desktop: place(every parked window, at: .active)
        Engine->>Lifecycle: quit()
    else SIGTERM
        Lifecycle->>Engine: stop()
        Engine->>Desktop: place(every parked window, at: .active)
    end
    Lifecycle->>Lifecycle: exit(EXIT_SUCCESS)
```

The default action for SIGTERM ends the process with every parked window still at the hidden edge. `Lifecycle.startWatchingSIGTERM` ignores the signal and takes it on a `DispatchSourceSignal` on the main queue.

### Unlock

Window events are dropped while the screen is locked, and a sweep run behind the login window reads every window as closed, so the registry and the workspaces drift apart. Unlocking closes the gap: `Lifecycle` runs both halves of the reconciliation, the removals first and the additions after.

```mermaid
sequenceDiagram
    ScreenLock->>Lifecycle: unlocked
    Lifecycle->>AXWindowObserver: resync()
    AXWindowObserver->>AXWindowEvents: runGC()
    AXWindowEvents->>Engine: destroyed(windowId), for each window that stopped answering
    loop each running application
        AXWindowObserver->>AXWindowEvents: resync(app)
        AXWindowEvents-->>AXWindowObserver: every window the application holds
    end
    AXWindowObserver-->>Lifecycle: the windows of every application
    Lifecycle->>Engine: resync(windows:)
    Engine->>Engine: assign the ones no workspace knows to the current workspace
```

The sweep runs first: a window it drops must not come back in the answer as one to adopt again. A window is reported dead only after two passes without an answer, because an application still coming back from sleep answers for none of its windows.

The answer holds every window, not only the ones this pass attached. A window created behind the login window was attached by the notification that announced it, and only the engine dropped the event, so it reaches the workspaces solely because `Engine.resync` reads the full set and keeps what no workspace knows.

### Window lifecycle

```mermaid
flowchart LR
    new[new or discovered window] -->|valid| managed[in a workspace]
    managed -->|minimized, full screen, destroyed, or moved to another native Space| unmanaged
    unmanaged -->|unminimized, or focused again| managed
```

A window out of reach cannot be parked, so OttoWM stops managing it instead of marking it. A parked window on screen proves the Space in front is OttoWM's own, so the managed windows missing from that Space are the ones that left. A window that comes back joins the current workspace, like a new one. A tab of a group in another workspace is the exception: it joins the group, and the user who focused it is followed there.

## Tabbed windows

macOS reports no tab membership, so OttoWM infers it. A tab group is one window to macOS: its tabs minimize, restore and move together.

### Discovery

```mermaid
sequenceDiagram
    participant Application
    participant AXWindowObserver
    participant Engine
    participant Workspaces
    participant TabGroups

    Application->>AXWindowObserver: the focused window changed
    Note over AXWindowObserver: Applications.subscribe hands the window to its application, which attaches it
    AXWindowObserver->>Engine: focused(window)
    Engine->>Workspaces: assign(window)
    Workspaces->>TabGroups: add(window)
    Note over TabGroups: reads how many tabs the window shows
    TabGroups-->>Workspaces: the group it joined
    Workspaces-->>Engine: the workspace of that group
    Note over Engine: a different workspace means the user is followed there
```

An application lists only the active tab of a group, and sends no notification when the user switches tabs. A background tab is discovered when it takes the focus, through this event or through the `Applications.subscribe` that `WindowSystem.focused()` reads through.

### Membership

```mermaid
flowchart LR
    win[window being assigned] --> tabs{more than one tab?}
    tabs -->|no| own["opens a new group,<br/>and is its representative"]
    tabs -->|yes| match{"same application, x, width and height,<br/>y within 10 pt of a representative?"}
    match -->|yes| join[joins that group]
    match -->|no| own
```

A group is keyed by a counter as macOS reuses window ids.

### Group events

| Event                                              | What OttoWM does                                                                                          |
|----------------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| A tab takes the focus for the first time           | Adds it to a group, and assigns it the workspace of that group. The group does not follow the new window. |
| The group of that tab is in another workspace      | Switches to that workspace.                                                                               |
| A workspace switch, or a move to another workspace | Places every member of the group together.                                                                |
| A tab closes                                       | Drops the window. A sibling keeps the focus, so no other window is chosen.                                |
| The group is minimized                             | macOS minimizes every member and names one. Drops all of them, then picks a new window to focus.          |
