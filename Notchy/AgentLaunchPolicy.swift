import Foundation

/// Decides which agent CLI a spawned terminal should auto-launch based on
/// the marker files present in the project directory. Pure so the launch
/// matrix is unit-testable; `TerminalManager` owns the filesystem probes.
enum AgentLaunchPolicy: Equatable {
    case claude
    case openCode
    case none

    /// Claude keeps priority when both markers exist, matching the historical
    /// behaviour of projects that carry a CLAUDE.md.
    static func resolve(hasClaudeMd: Bool, hasAgentsMd: Bool) -> AgentLaunchPolicy {
        if hasClaudeMd { return .claude }
        if hasAgentsMd { return .openCode }
        return .none
    }

    /// The CLI appended after `cd <dir> && clear`; nil leaves a bare shell.
    var launchCommand: String? {
        switch self {
        case .claude: return "claude"
        case .openCode: return "opencode"
        case .none: return nil
        }
    }
}
