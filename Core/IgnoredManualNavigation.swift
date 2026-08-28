/// Model that remembers when the next manual navigation is OttoWM's own doing. Bringing
/// the desktop back to front means focusing some managed window, and when that window is
/// parked, macOS reports the focus as the user navigating to it; answering would switch
/// to that window's workspace instead of the one the user asked for.
struct IgnoredManualNavigation {
    private var ignoresNext = false

    /// Ignores the next manual navigation, once.
    mutating func record() {
        ignoresNext = true
    }

    /// - Returns: `true` when this navigation is the one to ignore, consuming the record.
    mutating func take() -> Bool {
        defer { ignoresNext = false }
        return ignoresNext
    }
}
