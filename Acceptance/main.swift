// Scenario, a window sent to another workspace parks at the hidden edge and comes back,
// and the desk it was standing on goes with the workspace it belongs to. The restart
// hotkey picks up a binding the run adds while it is up, and the quit hotkey ends it,
// with whatever is parked when it fires handed back before OttoWM goes.

let session = Session.start()

report("posting lopt-shift-2")
moveWindowToWorkspace(2)
session.expect("the \(session.movable.name) window parked at the hidden edge", [session.movable], session.isParked)
session.expect("the rest of the desk stayed where it was", session.others) { $0.isWhereItWas }

report("posting lopt-2")
switchToWorkspace(2)
session.expect("the \(session.movable.name) window came back", [session.movable]) { $0.isWhereItWas }
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
session.expect("the \(session.movable.name) window parked again", [session.movable], session.isParked)

report("posting hyper-q")
quit()
session.waitForExit()
session.expect("the whole desk came back", session.subjects) { $0.isWhereItWas }

session.finish()

report("PASSED")
