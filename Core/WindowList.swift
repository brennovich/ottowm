import CoreGraphics
import Foundation

func onScreenWindowIds(from windowInfoList: [[String: Any]]) -> Set<CGWindowID> {
    var ids: Set<CGWindowID> = []
    for info in windowInfoList {
        if let number = info[kCGWindowNumber as String] as? NSNumber {
            ids.insert(CGWindowID(number.uint32Value))
        }
    }
    return ids
}
