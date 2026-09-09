import CoreGraphics

// Scenario, the focus hotkeys walk the focus around a desk arranged in the four quarters
// of the screen. The window actions take the window they are pointed at to a frame the run
// works out for itself, and put it back on the second press. One of the desk's windows
// shows two tabs, and what is asked of either of them is asked of the window both stand in.
// A window sent to another workspace parks at the hidden edge and comes back, and the desk
// it was standing on goes with the workspace it belongs to. The restart hotkey picks up a
// binding the run adds while it is up, and the quit hotkey ends it, with whatever is parked
// when it fires handed back before OttoWM goes.

let session = Session.start(arranged: true, tabbed: true)
let movable = session.movable
let terminal = session.subject(named: "Terminal")

guard let tab = session.backgroundTab else { fail("the desk staged no tab to drive") }

// The focus starts on the TextEdit window at the bottom right, so four moves walk it
// around the grid and back home, which is where the workspace scene below expects it.
report("posting lopt-k")
focusNeighbor(.north)
session.expectFocused(session.subject(named: "Safari"))

report("posting lopt-h")
focusNeighbor(.west)
session.expectFocused(session.subject(named: "Finder"))

report("posting lopt-j")
focusNeighbor(.south)
session.expectFocused(terminal)

report("posting lopt-l")
focusNeighbor(.east)
session.expectFocused(movable)

// The window actions all act on the focused window, which the walk above left on the
// movable one. Every scene starts from the frame the desk arranged that window at, so a
// scene can be added or dropped without the ones around it noticing.
let start = movable.originalFrame

movable.putBack()
report("posting lopt-ctrl-c")
centerWindow()
session.expect("the \(movable.name) window centered", [movable]) { $0.stands(at: centeredFrame(start.size)) }

movable.putBack()
report("posting lopt-shift-l")
moveWindow(.east)
session.expect("the \(movable.name) window moved \(Int(moveWindowStep))pt east", [movable]) {
    $0.stands(at: start.offsetBy(dx: moveWindowStep, dy: 0))
}

// A resize keeps the top left corner where it is.
movable.putBack()
report("posting lopt-ctrl-shift-l")
resizeWindow(.wider)
session.expect("the \(movable.name) window grew \(Int(moveWindowStep))pt wider", [movable]) {
    $0.stands(at: CGRect(origin: start.origin, size: CGSize(width: start.width + moveWindowStep, height: start.height)))
}

movable.putBack()
report("posting lopt-ctrl-shift-h")
resizeWindow(.narrower)
session.expect("the \(movable.name) window shrank \(Int(moveWindowStep))pt narrower", [movable]) {
    $0.stands(at: CGRect(origin: start.origin, size: CGSize(width: start.width - moveWindowStep, height: start.height)))
}

// A fill and a maximize both put the window back on the second press, and the frame they
// put it back to is the one it was standing at when the first press filled it.
for direction in [Direction.west, .east] {
    movable.putBack()
    report("posting lopt-ctrl-\(direction == .west ? "h" : "l")")
    fillHalf(direction)
    session.expect("the \(movable.name) window filled the \(direction.rawValue) half", [movable]) {
        $0.stands(at: filledFrame(direction), sizedWithin: refitTolerance)
    }

    report("posting lopt-ctrl-\(direction == .west ? "h" : "l") again")
    fillHalf(direction)
    session.expect("the \(movable.name) window went back to where it filled from", [movable]) { $0.isAsItWas }
}

movable.putBack()
report("posting lopt-ctrl-m")
toggleMaximize()
session.expect("the \(movable.name) window maximized", [movable]) {
    $0.stands(at: maximizedFrame(), sizedWithin: refitTolerance)
}

report("posting lopt-ctrl-m again")
toggleMaximize()
session.expect("the \(movable.name) window went back to where it maximized from", [movable]) { $0.isAsItWas }

// The workspace scenes below read the frame every window started at, which the actions
// above left the movable one away from.
movable.putBack()

// The maximize belongs to the window rather than to the tab that asked for it, so the tab
// standing behind knows the frame to go back to. Pressing the same key with that one in
// front puts the window back rather than filling a screen it already fills.
report("posting lopt-ctrl-m with the \(terminal.name) tab in front")
terminal.focus()
toggleMaximize()
session.expect("the tabbed window maximized", [terminal]) {
    $0.stands(at: maximizedFrame(), sizedWithin: refitTolerance)
}

report("bringing the \(tab.name) forward and posting lopt-ctrl-m")
tab.bringToFront()
tab.focus()
toggleMaximize()
session.expect("the tabbed window went back to where it maximized from", [tab]) {
    $0.stands(at: terminal.originalFrame, sizedWithin: refitTolerance)
}

// A tabbed window is as many windows as it has tabs, and a workspace takes all of them or
// the ones left behind stand on a desk that has been left.
let standing = session.subjects.filter { $0.name != terminal.name }

report("posting lopt-shift-3 with the tabbed window focused")
terminal.bringToFront()
terminal.focus()
moveWindowToWorkspace(3)
session.expect("the tabbed window parked", [terminal], session.isParked)
session.expect("the rest of the desk stayed where it was", standing) { $0.isWhereItWas }

report("posting lopt-3")
switchToWorkspace(3)
session.expect("the tabbed window came back", [terminal]) { $0.isWhereItWas }
session.expect("the rest of the desk parked", standing, session.isParked)

eventually("the tabbed window still shows both of its tabs") {
    let tabs = tabButtons(of: terminal.window).count

    return tabs == 2 ? nil : "the tab bar shows \(tabs)"
}

report("posting lopt-shift-1 and lopt-1 to take the tabbed window home")
terminal.focus()
moveWindowToWorkspace(1)
switchToWorkspace(1)
session.expect("the whole desk is back on the workspace it started on", session.subjects) { $0.isWhereItWas }

report("posting lopt-shift-2")
movable.focus()
moveWindowToWorkspace(2)
session.expect("the \(movable.name) window parked at the hidden edge", [movable], session.isParked)
session.expect("the rest of the desk stayed where it was", session.others) { $0.isWhereItWas }

report("posting lopt-2")
switchToWorkspace(2)
session.expect("the \(movable.name) window came back", [movable]) { $0.isWhereItWas }
session.expect("the rest of the desk parked", session.others, session.isParked)

report("binding lopt-5 to workspace 1 and posting hyper-r")
session.rebind("lopt-5 = switch-to-workspace 1")
restart()
session.waitForReload()

// Nothing was bound to lopt-5 when OttoWM launched, so the desk moving is the reload
// having read the file again.
report("posting lopt-5")
switchToWorkspace(5)
session.expect("the rest of the desk came back", session.others) { $0.isWhereItWas }
session.expect("the \(movable.name) window parked again", [movable], session.isParked)

report("posting hyper-q")
quit()
session.waitForExit()
session.expect("the whole desk came back", session.subjects) { $0.isWhereItWas }

session.finish()

report("PASSED")
