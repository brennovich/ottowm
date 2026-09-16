import CoreGraphics
import XCTest

final class SavedStateTests: XCTestCase {
    func testKeepsOnlyTheGivenWindows() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        func state(_ windowIds: [CGWindowID]) -> SavedState {
            var workspace = Workspace()
            windowIds.forEach { workspace.add($0) }
            let frames = Dictionary(uniqueKeysWithValues: windowIds.map { ($0, frame) })
            return SavedState(
                display: .standard,
                workspaces: Workspaces.Record(current: 1, workspaces: [1: workspace]),
                parkedWindows: windowIds.map { ParkedWindow(windowId: $0, parkedFrom: frame) },
                originalFrames: frames,
                displayLayouts: [Display.standard.id: frames]
            )
        }

        XCTAssertEqual(state([100, 200]).keeping([100]), state([100]))
    }
}
