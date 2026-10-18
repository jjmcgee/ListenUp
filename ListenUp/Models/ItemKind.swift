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

/// Supported audio playback rates across iPhone, CarPlay, Lock Screen, and Apple Watch.
public struct PlaybackSpeed: Sendable {
    public static let supportedRates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5]
    public static let defaultRate: Float = 1.0
    public static let userDefaultsKey = "preferredPlaybackRate"
}
