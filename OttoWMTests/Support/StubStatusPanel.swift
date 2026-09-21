final class StubStatusPanel: StatusPanel {
    private(set) var isVisible = false
    private(set) var rendered: [StatusReport] = []
    var perform: ((StatusAction) -> Void)?

    func render(_ report: StatusReport) {
        rendered.append(report)
    }

    func show() {
        isVisible = true
    }

    func hide() {
        isVisible = false
    }
}
