import Foundation

/// Capacity and claim rules for the pool of pre-spawned warm terminals.
/// Kept pure (no AppKit, no SwiftTerm) so the fill/claim behaviour is
/// unit-testable; `TerminalManager` owns the actual views.
enum WarmPoolPolicy {
    /// Idle shells are cheap (~10-20 MB RSS each) but not free. Three covers
    /// the common burst of opening several tabs in quick succession while the
    /// staggered fill timer re-arms behind the visible spawn.
    static let capacity = 3

    /// How many warm spawns are still needed. `inFlight` counts a spawn that
    /// is scheduled but not finished, so repeated prepare calls in the same
    /// fill window don't over-fill past capacity.
    static func deficit(liveCount: Int, inFlight: Int, capacity: Int = WarmPoolPolicy.capacity) -> Int {
        max(0, capacity - liveCount - inFlight)
    }

    /// Index within the pool to claim: the most recently spawned alive shell.
    /// LIFO keeps older shells available for later claims. Returns nil when
    /// there is nothing alive to claim (caller falls through to cold spawn).
    static func claimIndex(aliveFlags: [Bool]) -> Int? {
        aliveFlags.lastIndex(where: { $0 })
    }

    /// Indices of entries whose shell already exited (e.g. a login script
    /// that dies immediately). The caller discards these before claiming.
    static func deadIndices(aliveFlags: [Bool]) -> [Int] {
        aliveFlags.indices.filter { !aliveFlags[$0] }
    }
}
