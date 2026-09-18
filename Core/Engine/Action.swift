enum Action: Equatable {
    case switchToWorkspace(Int)
    case moveWindowToWorkspace(Int)
    case focus(Direction)
    case moveWindow(Direction)
    case resize(Resize.Change)
    case centerWindow
    case maximize
    case tile(Direction)
}
