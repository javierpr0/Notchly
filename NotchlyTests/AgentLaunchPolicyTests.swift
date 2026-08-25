import XCTest

final class AgentLaunchPolicyTests: XCTestCase {
    func testClaudeMdLaunchesClaude() {
        XCTAssertEqual(AgentLaunchPolicy.resolve(hasClaudeMd: true, hasAgentsMd: false), .claude)
        XCTAssertEqual(AgentLaunchPolicy.resolve(hasClaudeMd: true, hasAgentsMd: false).launchCommand, "claude")
    }

    func testAgentsMdAloneLaunchesOpenCode() {
        XCTAssertEqual(AgentLaunchPolicy.resolve(hasClaudeMd: false, hasAgentsMd: true), .openCode)
        XCTAssertEqual(AgentLaunchPolicy.resolve(hasClaudeMd: false, hasAgentsMd: true).launchCommand, "opencode")
    }

    func testClaudeWinsWhenBothMarkersExist() {
        // Projects carrying both files keep the historical behaviour.
        XCTAssertEqual(AgentLaunchPolicy.resolve(hasClaudeMd: true, hasAgentsMd: true), .claude)
    }

    func testNoMarkerLeavesABareShell() {
        XCTAssertEqual(AgentLaunchPolicy.resolve(hasClaudeMd: false, hasAgentsMd: false), .none)
        XCTAssertNil(AgentLaunchPolicy.none.launchCommand)
    }
}
