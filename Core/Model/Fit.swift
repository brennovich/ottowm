import CoreGraphics

/// Maps a frame from one visible frame into another, so a frame remembered on the display
/// left still fits the display entered or its new resolution.
///
/// On each axis the frame keeps the same fraction of the free space it had before, so a
/// frame flush against an edge stays flush and a centered one stays centered.
struct Fit: Equatable {
    let from: CGRect
    let into: CGRect

    func frame(_ frame: CGRect) -> CGRect {
        let size = CGSize(width: min(frame.width, into.width), height: min(frame.height, into.height))

        return CGRect(
            x: into.minX + share(frame.minX - from.minX, of: from.width - frame.width) * (into.width - size.width),
            y: into.minY + share(frame.minY - from.minY, of: from.height - frame.height) * (into.height - size.height),
            width: size.width,
            height: size.height
        )
    }

    private func share(_ offset: CGFloat, of room: CGFloat) -> CGFloat {
        guard room > 0 else { return 0 }
        return min(max(offset / room, 0), 1)
    }
}
