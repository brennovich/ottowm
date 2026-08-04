# Architecture

OttoWM is a headless agent (`App/main.swift` → `AppDelegate`) that fakes virtual workspaces on a
single native macOS Space. Everything runs on the main run loop; there is no concurrency.

## Layers

```mermaid
flowchart TB
    subgraph inputs[Inputs]
        AXWindowObserver
        HotkeyEventTap
        ConfigFile
    end

    subgraph core[Model]
        Engine
        Workspaces
        TabGroups
    end

    subgraph os[macOS boundary]
        Desktop[Desktop<br/>OffscreenParkingDesktop]
        Screen
        AXWindow
        MainScreen
    end

    AXWindowObserver -->|WindowEvent| Engine
    ConfigFile -->|Config: KeyCombo → Action| HotkeyEventTap
    HotkeyEventTap -->|Action| Engine
    Engine --> Workspaces
    Workspaces --> TabGroups
    Engine -->|place / focus / recover| Desktop
    Engine -->|focused / shows| Screen
    Desktop --> AXWindow
    Desktop --> MainScreen
    Screen --> AXWindow
```

| Component | Role |
|---|---|
| `Engine` | Orchestrator. Turns events and hotkeys into model updates plus desktop moves. Owns the admission gate (`isValidWindow`). |
| `Workspaces` | Pure model: window → workspace, per-workspace focus history, current workspace. No OS calls. |
| `TabGroups` | Infers macOS tab siblings by heuristic (app name + identical frame + `tabCount > 1`); a group moves as a unit and stays where it is, so a window joining one lands in the group's workspace rather than dragging the group to its own. |
| `Desktop` (`OffscreenParkingDesktop`) | The write side. Realizes `Placement` by parking storage windows in a 1px bottom-right sliver and restoring their captured frame. |
| `Screen` | The read side. Consistent, cached view of focused window and on-screen window ids. |
| `AXWindowObserver` | Per-app `AXObserver`s + `NSWorkspace` notifications → `WindowEvent`. Keeps the `AXUIElement ↔ CGWindowID` registry. An application lists only the active tab of a group in `kAXWindowsAttribute` and sends no notification when tabs switch, so a background tab cannot be enumerated at all: `focusedWindow()` adopts it into the registry at the one moment it is reachable, when it becomes focused. |
| `HotkeyEventTap` | Session `CGEventTap` on keyDown. Needed over Carbon hotkeys because only raw device flags distinguish left from right Option. |
| `Config` | The binding table: `KeyCombo` → `Action`, indexed by key code because the lookup runs in the event tap callback. Nothing else; a pure value. |
| `ConfigFile` | Where the configuration comes from: `load()` resolves `$OTTOWM_CONFIG` / XDG and falls back to the copy bundled in `Contents/Resources` only when there is no user file at all. A file that is there but does not parse comes back as a `ConfigError`, which `AppDelegate` turns into an exit rather than binding keys the user did not ask for. `parse()` is the pure parser for the line format (`key combo = action`, blank lines skipped, nothing else) and stops at the first problem; a combo bound twice keeps the last line, and two different combos one keystroke could satisfy (`alt-1` and `lalt-1`) are both kept, with the lookup picking between them in no guaranteed order. `KeyCombo` and `Action` are the two halves of a line and live beside it under `Core/Config`; `KeyCombo` owns the `NX_DEVICE*` bits that pin a modifier to one side, and `ConfigError` carries the offending line. |
| `OperationCache` | Holds one AX/CG read for the duration of an engine operation; each read is an IPC round trip. |

## Key types

```
WindowEvent  = created | focused | destroyed | minimized | unminimized
Action       = switchToWorkspace(n) | moveWindowToWorkspace(n)   // "switch-to-workspace n" in the config
KeyCombo     = (keyCode, [ModifierKey: Side])                    // "lopt-shift-1"
Placement    = active | storage
WindowSnapshot(id, appName, isStandard, isFullScreen, isMinimized, tabCount, frame)
```

Windows are identified by `CGWindowID`, obtained from the private `_AXUIElementGetWindow`.
Frames are in top-left (AX) coordinates; `MainScreen` flips Cocoa rects into that space.

## Flows

### Startup

```mermaid
sequenceDiagram
    AppDelegate->>ConfigFile: load()
    ConfigFile-->>AppDelegate: Config (user file, else bundled) or ConfigError
    Note right of AppDelegate: read first: a rejected file exits before any window moves
    AppDelegate->>AXWindowObserver: start(handler)
    AXWindowObserver-->>AppDelegate: [WindowSnapshot] discovered while registering
    AppDelegate->>Engine: start(windows)
    Engine->>Desktop: recover(windows)
    Note right of Desktop: un-park windows left at the hidden edge by a previous run
    Desktop-->>Engine: [WindowSnapshot] at the frames they were recovered to
    Engine->>Workspaces: assign every window to workspace 1
    Engine->>Desktop: startWatchingForManualNavigation
    AppDelegate->>HotkeyEventTap: start()
```

### Workspace switch

```mermaid
sequenceDiagram
    HotkeyEventTap->>Engine: switchToWorkspace(n)
    Engine->>Screen: showsAny(managed)?
    Engine->>Workspaces: switchTo(n, leavingFocusOn: focused)
    Workspaces-->>Engine: (toActive, toStorage)
    Engine->>Desktop: place(id, .active) / place(id, .storage)
    alt desktop was in front
        Engine->>Desktop: focus(nextWindowToFocus)
    else another native Space was in front
        Engine->>Desktop: returnToDesktop (focus any managed window)
    end
```

The whole operation runs inside `Screen.duringOperation`, so the focused window and the
on-screen list are each read at most once.

### Manual navigation (Cmd-Tab / Dock / Mission Control)

The user can reach a parked window behind OttoWM's back. Two detectors, one handler:

- A `.focused` event for a window whose placement is `.storage` (same native Space).
- `activeSpaceDidChangeNotification` with a hidden window focused (from another Space).

`handleManualNavigation` then switches the model to that window's workspace, so OttoWM follows
the user rather than fighting them. A one-shot `ignoreNextManualNavigation` flag suppresses the
echo of a focus OttoWM itself caused.

### Window lifecycle

```mermaid
flowchart LR
    created -->|valid| assigned[assigned to current workspace]
    assigned -->|minimized / fullscreen / destroyed| unmanaged
    unmanaged -->|unminimized, refocused| assigned
```

A window out of reach cannot be parked, so it stops being managed rather than being flagged.
Anything coming back joins whatever workspace is current, like a brand-new window — unless it is a
tab of a group living elsewhere, which wins: the window is assigned there and parked, and a user who
reached it by focusing it is followed to that workspace.

## Invariants

- `isValidWindow` is the single admission gate: non-zero id, standard subrole, not fullscreen,
  not minimized, and currently on screen.
- Every window the model records is one the registry can resolve. A window `Engine` cannot look up
  cannot be placed, so it would sit visible on every workspace: anything reaching `Engine`, the
  focused-window read included, is registered on the way in.
- The model never records a frame the desktop has already changed: `recover` returns the windows at
  the frame it left them, because `TabGroups` matches siblings by frame.
- Only `Desktop` moves windows; `Engine` never touches AX geometry directly.
- `Workspaces` is pure and fully unit-testable; `Desktop`/`Screen`/`Window` are protocols with
  stubs in `OttoWMTests`.
- A parked window's original frame lives in `OffscreenParkingDesktop.hiddenWindowFrames`;
  `forget` drops it when a window leaves management.
