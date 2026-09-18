import CoreGraphics

extension CGEventFlags {
    static let leftCommand: CGEventFlags = [.maskCommand, CGEventFlags(rawValue: 0x8)]
    static let rightCommand: CGEventFlags = [.maskCommand, CGEventFlags(rawValue: 0x10)]
    static let leftControl: CGEventFlags = [.maskControl, CGEventFlags(rawValue: 0x1)]
    static let leftOption: CGEventFlags = [.maskAlternate, CGEventFlags(rawValue: 0x20)]
    static let rightOption: CGEventFlags = [.maskAlternate, CGEventFlags(rawValue: 0x40)]
    static let leftShift: CGEventFlags = [.maskShift, CGEventFlags(rawValue: 0x2)]
}
