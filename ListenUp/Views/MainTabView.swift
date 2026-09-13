import SwiftUI
import SwiftData

/// Root coordinator tab view managing primary app navigation,
/// floating glass bottom navigation bar, mini-player dock, and search coordination.
public struct MainTabView: View {
    @Environment(AudioPlayerManager.self) private var player
    
    @State private var selectedTab: NavTab = .library
    @State private var isSearchActive: Bool = false
    @State private var searchText: String = ""
    @State private var isShowingFullPlayer: Bool = false
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            // Main tab content (ignores keyboard to keep background full-bleed)
            Group {
                if isSearchActive {
                    SearchView(searchText: searchText)
                } else {
                    switch selectedTab {
                    case .library:
                        LibraryView()
                    case .profile:
                        ProfileView()
                    case .settings:
                        SettingsView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            
            // Bottom Floating Controls: MiniPlayer + FloatingNavBar
            // Automatically animates directly above the keyboard when search field is focused
            VStack(spacing: 8) {
                if player.currentItem != nil && !isSearchActive {
                    MiniPlayerView(player: player) {
                        isShowingFullPlayer = true
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                FloatingNavBar(
                    selectedTab: $selectedTab,
                    isSearchActive: $isSearchActive,
                    searchText: $searchText
                )
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: player.currentItem != nil)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isSearchActive)
        }
        .sheet(isPresented: $isShowingFullPlayer) {
            FullPlayerView(player: player)
        }
    }
}

#Preview {
    MainTabView()
        .environment(AudioPlayerManager())
        .modelContainer(for: LibraryItem.self, inMemory: true)
}
