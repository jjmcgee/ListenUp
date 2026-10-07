import SwiftUI
import SwiftData

/// Centralized coordinator for app tab selection, sheet presentations, and deep linking from widgets.
@Observable
@MainActor
public final class NavigationCoordinator {
    
    public static let shared = NavigationCoordinator()
    
    public var selectedTab: NavTab = .library
    public var isShowingFullPlayer: Bool = false
    
    public init() {}
    
    /// Handles incoming deep links from WidgetKit (e.g., `listenup://play?id=...`, `listenup://stats`).
    public func handleURL(_ url: URL, in context: ModelContext, player: AudioPlayerManager) {
        guard url.scheme?.lowercased() == "listenup" else { return }
        
        let host = url.host?.lowercased() ?? ""
        
        switch host {
        case "stats", "profile":
            selectedTab = .profile
            
        case "nowplaying", "player":
            if player.currentItem == nil {
                let descriptor = FetchDescriptor<LibraryItem>(
                    predicate: #Predicate { $0.parent == nil && !$0.isDeletedFromLibrary },
                    sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
                )
                if let items = try? context.fetch(descriptor), let item = items.first {
                    player.prepare(item: item)
                }
            }
            if player.currentItem != nil {
                isShowingFullPlayer = true
            }
            
        case "play", "book":
            // Extract UUID from query parameter or path
            let idString: String?
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItem = components.queryItems?.first(where: { $0.name == "id" })?.value {
                idString = queryItem
            } else {
                idString = url.pathComponents.filter({ $0 != "/" }).last
            }
            
            if let idString = idString, let itemID = UUID(uuidString: idString) {
                let descriptor = FetchDescriptor<LibraryItem>(
                    predicate: #Predicate { $0.id == itemID }
                )
                if let items = try? context.fetch(descriptor), let item = items.first {
                    player.play(item: item)
                    isShowingFullPlayer = true
                }
            }
            
        default:
            break
        }
    }
}

