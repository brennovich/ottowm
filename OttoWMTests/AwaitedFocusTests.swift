import CoreGraphics
import XCTest

final class AwaitedFocusTests: XCTestCase {
    private enum Step {
        case request(CGWindowID)
        case settle(CGWindowID)
        case forget(CGWindowID)
    }

    func testEchoDetection() {
        let cases: [(name: String, steps: [Step], settling: CGWindowID, isEcho: Bool)] = [
            ("a window that was never requested", [], 100, false),
            ("the request still awaited", [.request(100)], 100, false),
            ("a request that was replaced", [.request(100), .request(200)], 100, true),
            ("the same request made twice", [.request(100), .request(100)], 100, false),
            (
                "a replaced request, after the one that replaced it settled",
                [.request(100), .request(200), .settle(200)],
                100,
                false
            ),
            (
                "a replaced request, after another replaced one settled",
                [.request(100), .request(200), .request(300), .settle(100)],
                200,
                true
            ),
            (
                "a replaced request, after the awaited one was forgotten",
                [.request(100), .request(200), .forget(200)],
                100,
                true
            ),
            (
                "a replaced request that was forgotten",
                [.request(100), .request(200), .request(300), .forget(100)],
                100,
                false
            ),
            (
                "a replaced request, after another replaced one was forgotten",
                [.request(100), .request(200), .request(300), .forget(100)],
                200,
                true
            ),
        ]

        for testCase in cases {
            var awaited = AwaitedFocus()
            for step in testCase.steps {
                switch step {
                case let .request(windowId): awaited.request(windowId)
                case let .settle(windowId): _ = awaited.settle(windowId)
                case let .forget(windowId): awaited.forget(windowId)
                }
            }

            XCTAssertEqual(awaited.settle(testCase.settling), testCase.isEcho, testCase.name)
        }
    }
}
