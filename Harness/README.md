# Harness

Shared machinery for the acceptance run in `Acceptance/` and the benchmark in `Benchmark/`. Both drive the app installed in `/Applications` the way a user does: real hotkeys through the event tap, real frames read back through the accessibility API. Nothing here imports the app's own code on purpose, the bundle under test is the one shipped in the release zip.

| File            | What it holds                                                                                           |
| --------------- | ------------------------------------------------------------------------------------------------------- |
| `Session.swift` | Stages the desk, launches the app, hands back the windows to drive, and undoes all of it on the way out |
| `AX.swift`      | The accessibility reads: a window's frame, an application's windows, a window's title, a menu item      |
| `Hotkeys.swift` | Posts the bundled key combos as real key events into the session event tap                              |
| `Report.swift`  | Output, failure, and the wait every check is built on                                                   |

There is no target of its own to build. Each run compiles the harness into its own binary, `make build/acceptance` and `make build/benchmark`, which is also how CI builds both before it grants permissions to anything.

## Before a run

`make install` first: the harness drives `/Applications/OttoWM.app` and refuses to start without it. It launches that app itself, so it also refuses to start while another OttoWM is up, which would race it for the same hotkeys.

Whatever runs the harness needs Accessibility permission, the terminal running `make` locally, the process running the binary on CI. Posting events and reading frames both depend on it, and the harness says so and stops rather than measuring a desk it cannot see. The app needs its own grant.

The app is launched with `XDG_CONFIG_HOME` pointing at a staged copy of the bundled defaults, so whatever sits in the real `~/.config/ottowm` cannot change what the run is bound to. `Hotkeys.swift` posts the combos those defaults bind: left Option and left Option + Shift, with the device-dependent flag bits set by hand, since only the raw event flags tell the left Option key from the right one and System Events cannot produce them; and hyper + Q for the quit action, which needs no such bits because `hyper` takes either side of every modifier.

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

Safari is the exception to how the windows are opened. `open -a Safari` hands the page to whichever window is already up rather than putting a new one up, and a tab that is not the active one cannot be read through the accessibility API, so the second desk's page opens and is unfindable at the same time. Safari is asked for an empty window first and handed the page after, because the page goes to whichever window is frontmost. The ask goes through `File > New Window` in its menu bar, which the Accessibility permission the run already holds is enough to press. Asking for a new document the scriptable way, which is Safari's own word for a window, would want an Automation grant instead, and a machine with nobody at it never gets one: `osascript` sits on the request for the two minute AppleEvent timeout and says nothing legible about why.

Windows the run opened are closed on the way out and applications it launched are quit, an application that was already there keeps the windows that were already its own. The staged files go with them. The acceptance run ends OttoWM with the quit hotkey and waits it out; the cleanup still signals whatever is left running, and kills it if it will not go, because the next run refuses to start while one is up and CI runs them back to back. All of it happens on a failure too, `fail` unwinds the same stack before it exits.

## What a run gets

`Session.start` hands back the windows as `Subject`s, each one carrying the frame it read once everything had settled, which is the frame it is owed back after every switch:

- `subject.isWhereItWas` — within 2px of that frame.
- `session.isParked(subject)` — at the hidden edge, allowing the same 10px `HiddenEdge.holds` allows, since macOS clamps a window parked 1px past the right edge back by an unspecified amount.
- `subject.focus()` — the hotkeys act on the focused window and a switch hands the focus to whichever window it pleases, so whoever wants this one moved says so first. Asked for the way `Core/AXWindow.focused()` asks, the focused window of the frontmost application, because that is the window a hotkey will act on.

`session.expect` waits for every subject to satisfy an expectation and says which ones do not and where they stand when it gives up. It is built on `eventually`, which polls until its probe is satisfied and ends the run with what the probe last saw when it never is.
