import CoreGraphics

enum HotkeyAction: Equatable {
    case switchToVirtualSpace(Int)
    case moveWindowToVirtualSpace(Int)
}

// Device-dependent CGEventFlags bits (NX_DEVICELALTKEYMASK / NX_DEVICERALTKEYMASK):
// the only public way to tell the two Option keys apart.
private let leftOptionDeviceBit: UInt64 = 0x20
private let rightOptionDeviceBit: UInt64 = 0x40

private let virtualSpaceByKeyCode: [Int64: Int] = [18: 1, 19: 2, 20: 3, 21: 4]

func hotkeyAction(keyCode: Int64, flags: CGEventFlags) -> HotkeyAction? {
    guard let virtualSpace = virtualSpaceByKeyCode[keyCode],
          flags.contains(.maskAlternate),
          flags.rawValue & leftOptionDeviceBit != 0,
          flags.rawValue & rightOptionDeviceBit == 0,
          !flags.contains(.maskCommand),
          !flags.contains(.maskControl)
    else { return nil }

    return flags.contains(.maskShift)
        ? .moveWindowToVirtualSpace(virtualSpace)
        : .switchToVirtualSpace(virtualSpace)
}
