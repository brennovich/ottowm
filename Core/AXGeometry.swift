import ApplicationServices
import CoreGraphics

func decodeCGPoint(_ value: AXValue) -> CGPoint? {
    guard AXValueGetType(value) == .cgPoint else { return nil }
    var point = CGPoint.zero
    return AXValueGetValue(value, .cgPoint, &point) ? point : nil
}

func decodeCGSize(_ value: AXValue) -> CGSize? {
    guard AXValueGetType(value) == .cgSize else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(value, .cgSize, &size) ? size : nil
}

func encodeCGPoint(_ point: CGPoint) -> AXValue {
    var point = point
    return AXValueCreate(.cgPoint, &point)!
}

func encodeCGSize(_ size: CGSize) -> AXValue {
    var size = size
    return AXValueCreate(.cgSize, &size)!
}
