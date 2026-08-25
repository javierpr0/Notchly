import XCTest

final class WarmPoolPolicyTests: XCTestCase {
    func testDeficitEmptyPoolRequestsFullCapacity() {
        XCTAssertEqual(WarmPoolPolicy.deficit(liveCount: 0, inFlight: 0), WarmPoolPolicy.capacity)
    }

    func testDeficitCountsInFlightAgainstCapacity() {
        XCTAssertEqual(WarmPoolPolicy.deficit(liveCount: 2, inFlight: 1), 0)
        XCTAssertEqual(WarmPoolPolicy.deficit(liveCount: 1, inFlight: 1), 1)
    }

    func testDeficitNeverNegative() {
        XCTAssertEqual(WarmPoolPolicy.deficit(liveCount: WarmPoolPolicy.capacity + 2, inFlight: 0), 0)
    }

    func testClaimPicksLastAliveEntryLIFO() {
        XCTAssertEqual(WarmPoolPolicy.claimIndex(aliveFlags: [false, true, false, true]), 3)
        XCTAssertEqual(WarmPoolPolicy.claimIndex(aliveFlags: [true]), 0)
    }

    func testClaimReturnsNilWhenAllDead() {
        XCTAssertNil(WarmPoolPolicy.claimIndex(aliveFlags: [false, false]))
        XCTAssertNil(WarmPoolPolicy.claimIndex(aliveFlags: []))
    }

    func testDeadIndicesSelectsOnlyDeadEntries() {
        XCTAssertEqual(WarmPoolPolicy.deadIndices(aliveFlags: [true, false, true]), [1])
        XCTAssertEqual(WarmPoolPolicy.deadIndices(aliveFlags: [false]), [0])
        XCTAssertEqual(WarmPoolPolicy.deadIndices(aliveFlags: []), [])
    }
}
