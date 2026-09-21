import XCTest

final class RequirementsTests: XCTestCase {
    private let requirement = Requirement(
        name: "Automatically hide and show the Dock",
        domain: "com.apple.dock",
        key: "autohide",
        expected: true,
        absentValue: false
    )

    func testTheValueIsTheKeysOrTheMacOSDefaultWhenTheKeyIsAbsent() {
        let cases: [(name: String, requirement: Requirement, read: Bool?, value: Bool)] = [
            ("key holds a value", requirement, true, true),
            ("key absent", requirement, nil, false),
            ("key absent, macOS default on", Requirements.all[2], nil, true),
        ]

        for testCase in cases {
            XCTAssertEqual(testCase.requirement.value { _, _ in testCase.read }, testCase.value, testCase.name)
        }
    }

    func testTheReadIsAskedForTheDomainAndKeyOfTheRequirement() {
        var asked: [(String, String)] = []

        _ = requirement.value { domain, key in
            asked.append((domain, key))
            return nil
        }

        XCTAssertEqual(asked.map(\.0), ["com.apple.dock"])
        XCTAssertEqual(asked.map(\.1), ["autohide"])
    }

    func testTheFixCommandIsTheREADMELine() {
        XCTAssertEqual(requirement.fixCommand, "defaults write com.apple.dock autohide -bool true && killall Dock")
        XCTAssertEqual(
            Requirements.all[1].fixCommand,
            "defaults write com.apple.spaces spans-displays -bool false && killall Dock"
        )
    }
}
