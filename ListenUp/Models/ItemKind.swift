import Foundation

/// Represents the nature of an audio library node in the hierarchical tree.
public enum ItemKind: String, Codable, Sendable, CaseIterable {
    /// A standalone single audio file (.m4b, .m4a, .mp3).
    case singleFile
    
    /// A multi-part book containing an ordered sequence of child tracks
    /// that are treated seamlessly as a single continuous timeline.
    case multiPart
    
    /// A structural directory or container (e.g. "Pimsleur" -> "Level 1").
    case folder
    
    /// SF Symbol icon name.
    public var systemIconName: String {
        switch self {
        case .singleFile: return "headphones"
        case .multiPart: return "books.vertical.fill"
        case .folder: return "folder.fill"
        }
    }
}
