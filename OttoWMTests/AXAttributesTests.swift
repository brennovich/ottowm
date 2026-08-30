import ApplicationServices
import XCTest

final class AXAttributesTests: XCTestCase {
    private func encodeAXError(_ error: AXError) -> AXValue {
        var error = error
        return AXValueCreate(.axError, &error)!
    }

    func testDiscardsInlineErrorValues() {
        let values: [AnyObject] = [
            "AXStandardWindow" as NSString,
            encodeAXError(.attributeUnsupported),
            CGPoint(x: 10, y: 20).axValue,
        ]

        let result = values.discardingAXErrors

        XCTAssertEqual(result[0] as? String, "AXStandardWindow")
        XCTAssertNil(result[1])
        XCTAssertEqual(CGPoint(axValue: result[2]), CGPoint(x: 10, y: 20))
    }

    func testReadingAnUnsupportedAttributeYieldsNil() {
        let systemWide = AXUIElementCreateSystemWide()

        XCTAssertNil(systemWide.value(of: AXAttribute(rawValue: "AXNotAnAttribute")))
        XCTAssertNil(systemWide.elementValue(of: AXAttribute(rawValue: "AXNotAnAttribute")))
    }

    func testReadingUnsupportedAttributesLeavesThemAbsent() {
        let systemWide = AXUIElementCreateSystemWide()

        let unknown = AXAttribute(rawValue: "AXNotAnAttribute")

        XCTAssertNil(systemWide.values(of: [unknown])[unknown])
    }
}
