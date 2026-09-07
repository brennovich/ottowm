# Harness

Shared machinery for the acceptance run in `Acceptance/` and the benchmark in `Benchmark/`. Both drive the app installed in `/Applications` the way a user does: real hotkeys through the event tap, real frames read back through the accessibility API. Nothing here imports the app's own code on purpose, the bundle under test is the one shipped in the release zip.

| File            | What it holds                                                                                      |
| --------------- | -------------------------------------------------------------------------------------------------- |
| `Session.swift` | Launches the app, hands back the windows to drive, and undoes all of it on the way out             |
| `Desk.swift`    | Stages the configuration a run is bound to and the windows it drives, and opens each one           |
| `AX.swift`      | The accessibility reads: a window's frame, an application's windows, a window's title, a menu item |
| `Hotkeys.swift` | Posts the bundled key combos as real key events into the session event tap                         |
| `Screen.swift`  | Where the window actions take a window, worked out from the screen the same way the app does it   |
| `Tabs.swift`    | Makes a tabbed window out of two, and brings either of its tabs to the front                      |
| `Report.swift`  | Output, failure, and the wait every check is built on                                              |

There is no target of its own to build. Each run compiles the harness into its own binary, `make build/acceptance` and `make build/benchmark`, which is also how CI builds the one it is about to run before it grants permissions to anything.

## Before a run

`make install` first: the harness drives `/Applications/OttoWM.app` and refuses to start without it. It launches that app itself, so it also refuses to start while another OttoWM is up, which would race it for the same hotkeys.

Whatever runs the harness needs Accessibility permission, the terminal running `make` locally, the process running the binary on CI. Posting events and reading frames both depend on it, and the harness says so and stops rather than measuring a desk it cannot see. The app needs its own grant.

The app is launched with `XDG_CONFIG_HOME` pointing at a staged copy of the bundled defaults, so whatever sits in the real `~/.config/ottowm` cannot change what the run is bound to. `Hotkeys.swift` posts the combos those defaults bind: left Option and left Option + Shift, with the device-dependent flag bits set by hand, since only the raw event flags tell the left Option key from the right one and System Events cannot produce them; left Option + H/J/K/L for the focus moves, the same keys under Shift for the window moves and under Control for the fills; left Option + Control + C and + M for centering and maximizing; and hyper + Q and hyper + R for the quit and restart actions, which need no such bits because `hyper` takes either side of every modifier. `ctrl` and `shift` are named without a side in the defaults, so those carry the mask alone. `Session.rebind` appends a line to that staged copy, for a run that then posts hyper + R and drives the rest of itself through a key nothing was bound to when the app launched.

## The desk

A plausible one, a file browser, a terminal, a browser and an editor, because a workspace switch costs what the windows standing on it cost. Everything is opened after OttoWM is up so the engine sees the windows arrive:

| Application | Shows                                   |
| ----------- | --------------------------------------- |
| Finder      | A scratch directory named after the run |
| Terminal    | Sitting in that directory               |
| Safari      | A staged HTML page                      |
| TextEdit    | A staged text document                  |

The last window staged, the TextEdit document, is the one the hotkeys move between workspaces. The other three only ever move because the workspace they stand on was left. Every window is titled after the run and its instance and is claimed as it is found, so with more than one desk on screen the second Finder cannot answer to the first one's title.

`Session.start(instances:)` stages that many copies of the whole desk, so three is twelve windows rather than four. The benchmark exposes it as `--instances`; the acceptance run always takes one.

`Session.start(arranged:)` puts each instance's windows in the four quarters of the screen (Finder top left, Terminal bottom left, Safari top right, TextEdit bottom right) instead of wherever macOS chose, for a run that asserts which window a focus move lands on and has to know the geometry to do it. The acceptance run takes it; the benchmark leaves the desk where it landed.

`Session.start(tabbed:)` opens a second terminal window and merges the two into one window showing a tab of each, for a run that drives a window its application shows one tab of at a time. It hands that second tab back as `session.backgroundTab`, which is kept out of `session.subjects` because a tab that is not in front answers a frame that cannot change, and a check made over every subject would pass on it for nothing. The desk's own window is brought back to the front after the merge, which leaves whichever of the two it pleases there.

Merged rather than asked for: Terminal answers `Shell > New Tab` with a submenu of profiles, and pressing the parent or its first entry adds no tab, while whether a new document opens as a tab at all is a system setting the run does not own. `Window > Merge All Windows` is a flat item and takes what is already open, so it also takes every window the application has, which is why a tabbed desk stages one instance.

Safari is the exception to how the windows are opened. `open -a Safari` hands the page to whichever window is already up rather than putting a new one up, and a tab that is not the active one cannot be read through the accessibility API, so the second desk's page opens and is unfindable at the same time. Safari is asked for an empty window first and handed the page after, because the page goes to whichever window is frontmost. The ask goes through `File > New Window` in its menu bar, which the Accessibility permission the run already holds is enough to press. Asking for a new document the scriptable way, which is Safari's own word for a window, would want an Automation grant instead, and a machine with nobody at it never gets one: `osascript` sits on the request for the two minute AppleEvent timeout and says nothing legible about why.

Windows the run opened are closed on the way out and applications it launched are quit, an application that was already there keeps the windows that were already its own. The staged files go with them. The acceptance run ends OttoWM with the quit hotkey and waits it out; the cleanup still signals whatever is left running, and kills it if it will not go, because the next run refuses to start while one is up and CI runs them back to back. All of it happens on a failure too, `fail` unwinds the same stack before it exits.

## What a run gets

`Session.start` hands back the windows as `Subject`s, each one carrying the frame it read once everything had settled, which is the frame it takes back after every switch:

- `subject.isWhereItWas` — within 2px of that frame.
- `subject.stands(at:sizedWithin:)` — at a frame the scene worked out, the size included, which `isWhereItWas` says nothing about: a window still filling the screen is as much at its old origin as one put back. `Screen.swift` works out the frames the window actions take, mirroring `Core/OffscreenParkingDesktop.swift` and `Core/Half.swift` rather than importing them, so a change only one of them makes is a run that fails. The size is allowed more room than the origin because an application answers a size it can take where it keeps the position it is handed, Terminal to the nearest whole row.
- `subject.isAsItWas` — the frame it was read at, size included, and `subject.putBack()` writes it back for a scene that leaves the window elsewhere and is followed by one that reads where it started.
- `subject.bringToFront()` — the tab this window is, in front. Everything above reads the window an application lists, and a tabbed application lists one tab at a time; the others answer the frame they had when they last were in front, and answer a frame written to them without the window moving. The tab bar's buttons are pressed in turn rather than picked out by title, since Terminal titles each one after the process running in it.
- `session.isParked(subject)` — at the hidden edge, allowing the same 10px `HiddenEdge.holds` allows, since macOS clamps a window parked 1px past the right edge back by an unspecified amount.
- `subject.focus()` — the hotkeys act on the focused window and a switch hands the focus to whichever window it pleases, so whoever wants this one moved says so first. Asked for the way `Core/AXWindow.focused()` asks, the focused window of the frontmost application, because that is the window a hotkey will act on.
- `subject.lacksFocus()`: nil when the window holds that same focus, otherwise where the focus actually is.

`session.expect` waits for every subject to satisfy an expectation and says which ones do not and where they stand when it gives up. `session.expectFocused` waits the same way for one subject to take the focus. Both are built on `eventually`, which polls until its probe is satisfied and ends the run with what the probe last saw when it never is.
