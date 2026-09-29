final class StubAnchor: Anchor {
    private(set) var pinCount = 0
    private(set) var focusCount = 0
    private(set) var putAwayCount = 0

    func pin() {
        pinCount += 1
    }

    func focus() {
        focusCount += 1
    }

    func putAway() {
        putAwayCount += 1
    }
}
