import Foundation

/// Value type representing a user-created bookmark with a timestamp and optional custom note.
public struct UserBookmark: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var bookID: UUID
    public var title: String
    public var timestamp: Double
    public var createdAt: Date
    
    public init(
        id: UUID = UUID(),
        bookID: UUID,
        title: String,
        timestamp: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.title = title
        self.timestamp = timestamp
        self.createdAt = createdAt
    }
}
