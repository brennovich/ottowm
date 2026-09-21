import XCTest

final class RequirementsTests: XCTestCase {
    private let requirement = Requirement(
        name: "Hide and show the Dock",
        domain: "com.apple.dock",
        key: "autohide",
        expected: true,
        absentValue: false
    )

    func testTheValueIsTheOneUnderTheDomainAndKeyOfTheRequirement() {
        let cases: [(name: String, requirement: Requirement, read: (String, String) -> Bool?, value: Bool)] = [
            ("key holds a value", requirement, { $0 == "com.apple.dock" && $1 == "autohide" ? true : nil }, true),
            ("key absent", requirement, { _, _ in nil }, false),
            ("key absent, macOS default on", Requirements.all[2], { _, _ in nil }, true),
        ]

        for testCase in cases {
            XCTAssertEqual(testCase.requirement.value(read: testCase.read), testCase.value, testCase.name)
        }
    }

    func testTheFixCommandIsTheREADMELine() {
        XCTAssertEqual(requirement.fixCommand, "defaults write com.apple.dock autohide -bool true")
        XCTAssertEqual(Requirements.all[1].fixCommand, "defaults write com.apple.spaces spans-displays -bool false")
    }
}
