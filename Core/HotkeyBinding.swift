import CoreGraphics

enum HotkeyAction: Equatable {
    case switchToVirtualSpace(Int)
    case moveWindowToVirtualSpace(Int)
}

enum EventTapDecision: Equatable {
    case reenableAndPass
    case consume(HotkeyAction)
    case pass
}

func eventTapDecision(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> EventTapDecision {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        return .reenableAndPass
    }
    guard type == .keyDown, let action = hotkeyAction(keyCode: keyCode, flags: flags) else {
        return .pass
    }
    return .consume(action)
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
