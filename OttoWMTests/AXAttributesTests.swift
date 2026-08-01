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
            encodeCGPoint(CGPoint(x: 10, y: 20)),
        ]

        let result = discardingAXErrors(values)

        XCTAssertEqual(result[0] as? String, "AXStandardWindow")
        XCTAssertNil(result[1])
        XCTAssertEqual(axValue(result[2]).flatMap(decodeCGPoint), CGPoint(x: 10, y: 20))
    }

    func testReadingAnUnsupportedAttributeYieldsNil() {
        let systemWide = AXUIElementCreateSystemWide()

        XCTAssertNil(axAttribute(systemWide, "AXNotAnAttribute"))
        XCTAssertNil(axElement(systemWide, "AXNotAnAttribute"))
    }

    func testKeepsNonErrorValues() {
        let values: [AnyObject] = [true as NSNumber, encodeCGSize(CGSize(width: 8, height: 6))]

        let result = discardingAXErrors(values)

        XCTAssertEqual(result[0] as? Bool, true)
        XCTAssertEqual(axValue(result[1]).flatMap(decodeCGSize), CGSize(width: 8, height: 6))
    }
}
