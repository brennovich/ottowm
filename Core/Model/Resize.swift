import CoreGraphics

struct Resize: Equatable {
    enum Change: String, CaseIterable {
        case wider, narrower, taller, shorter
    }

    let change: Change
    let points: CGFloat

    func frame(resizing frame: CGRect, within bounds: CGRect) -> CGRect {
        var size = frame.size

        switch change {
        case .wider:
            size.width = min(frame.width + points, max(bounds.maxX - frame.minX, frame.width))
        case .taller:
            size.height = min(frame.height + points, max(bounds.maxY - frame.minY, frame.height))
        case .narrower:
            guard frame.width > points else { return frame }
            size.width = frame.width - points
        case .shorter:
            guard frame.height > points else { return frame }
            size.height = frame.height - points
        }

        return CGRect(origin: frame.origin, size: size)
    }
}
