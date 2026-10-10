final class StubAnchor: Anchor {
    private(set) var pinCount = 0
    private(set) var focusCount = 0
    private(set) var putAwayCount = 0
    private(set) var pinnedDisplays: [Display] = []

    func pin(on display: Display) {
        pinCount += 1
        pinnedDisplays.append(display)
    }

    func focus() {
        focusCount += 1
    }

    func putAway() {
        putAwayCount += 1
    }
}
