import Foundation

struct StoredCommand: Codable {
    var text: String
    var count: Int
    var lastUsed: Date
}

struct CommandFile: Codable {
    var commands: [StoredCommand]
}
