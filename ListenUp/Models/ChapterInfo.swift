import Foundation

/// Discrete chapter mark within an audiobook, either extracted from an M4A/M4B audio file
/// or mapped from a multi-part segment on the virtual timeline.
public struct ChapterInfo: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let index: Int
    public let title: String
    public let startTime: Double
    public let duration: Double
    
    public var endTime: Double {
        startTime + duration
    }
    
    public init(
        id: UUID = UUID(),
        index: Int,
        title: String,
        startTime: Double,
        duration: Double
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.startTime = max(0.0, startTime)
        self.duration = max(0.0, duration)
    }
}
