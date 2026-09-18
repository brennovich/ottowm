import CoreGraphics
import XCTest

final class AdmissionTests: EngineTestCase {
    func testAdmitsAnAdmissibleWindowOnScreen() {
        let win = add(StubWindow(id: 100))

        XCTAssertEqual(admission.verdict(for: win.snapshot()), .admit)
    }

    func testRetriesAWindowNotYetOnScreen() {
        offScreenWindowIds = [100]
        let win = add(StubWindow(id: 100))

        XCTAssertEqual(admission.verdict(for: win.snapshot()), .retry)
    }

    func testRetriesWhileAnotherNativeSpaceIsInFront() {
        let elsewhere = add(StubWindow(id: 100))
        workspaces.assign(elsewhere.snapshot(), to: 1)
        offScreenWindowIds = [100]

        let win = add(StubWindow(id: 200))

        XCTAssertEqual(admission.verdict(for: win.snapshot()), .retry)
    }

    /// The shape rules a window out for good, so it is refused rather than retried even
    /// when the desktop alone would call for another read.
    func testRefusesAWindowItsShapeRulesOutWhileAnotherNativeSpaceIsInFront() {
        let elsewhere = add(StubWindow(id: 100))
        workspaces.assign(elsewhere.snapshot(), to: 1)
        offScreenWindowIds = [100]

        let win = add(StubWindow(id: 200, isFullScreen: true))

        XCTAssertEqual(admission.verdict(for: win.snapshot()), .refuse)
    }

    func testTheDesktopIsInFrontWhileNoWindowIsManaged() {
        XCTAssertTrue(admission.isDesktopInFront)
    }

    func testTheDesktopIsNotInFrontWhileTheScreenShowsNoManagedWindow() {
        let win = add(StubWindow(id: 100))
        workspaces.assign(win.snapshot(), to: 1)
        offScreenWindowIds = [100]

        focused = add(StubWindow(id: 200))

        XCTAssertFalse(admission.isDesktopInFront)
    }

    func testTheDesktopIsInFrontWhenTheFocusedWindowBelongsToAManagedTabGroup() {
        let tab1 = add(StubWindow(id: 300, appName: "Terminal", frame: tabFrame, tabCount: 2))
        workspaces.assign(tab1.snapshot(), to: 1)
        let tab2 = add(StubWindow(id: 301, appName: "Terminal", frame: tabFrame, tabCount: 2))
        offScreenWindowIds = [300]

        focused = tab2

        XCTAssertTrue(admission.isDesktopInFront)
    }
}
