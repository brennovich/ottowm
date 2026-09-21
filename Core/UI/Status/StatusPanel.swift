import Foundation

/// What a button of the About window asks for.
enum StatusAction: Equatable {
    case openSettings
    case revealConfig
    case createConfig
    case reload
    case copyDiagnostics
    case copyFixes
}

/// The window the About report is shown in. `StatusWindow` is the one the app runs with.
protocol StatusPanel: AnyObject {
    var isVisible: Bool { get }
    var perform: ((StatusAction) -> Void)? { get set }

    func render(_ report: StatusReport)
    func show()
    func hide()
}
