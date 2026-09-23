import SwiftUI
import SwiftData

/// Root coordinator tab view managing primary app navigation,
/// floating glass bottom navigation bar, mini-player dock, and search coordination.
public struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayerManager.self) private var player
    @Environment(NavigationCoordinator.self) private var navCoordinator: NavigationCoordinator?
    
    @State private var internalSelectedTab: NavTab = .library
    @State private var isSearchActive: Bool = false
    @State private var searchText: String = ""
    @State private var internalShowingFullPlayer: Bool = false
    
    private var selectedTabBinding: Binding<NavTab> {
        Binding(
            get: { navCoordinator?.selectedTab ?? internalSelectedTab },
            set: {
                if let nav = navCoordinator {
                    nav.selectedTab = $0
                } else {
                    internalSelectedTab = $0
                }
            }
        )
    }
    
    private var isShowingFullPlayerBinding: Binding<Bool> {
        Binding(
            get: { navCoordinator?.isShowingFullPlayer ?? internalShowingFullPlayer },
            set: {
                if let nav = navCoordinator {
                    nav.isShowingFullPlayer = $0
                } else {
                    internalShowingFullPlayer = $0
                }
            }
        )
    }
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            // Main tab content (ignores keyboard to keep background full-bleed)
            Group {
                if isSearchActive {
                    SearchView(searchText: searchText)
                } else {
                    switch selectedTabBinding.wrappedValue {
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
                        isShowingFullPlayerBinding.wrappedValue = true
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                FloatingNavBar(
                    selectedTab: selectedTabBinding,
                    isSearchActive: $isSearchActive,
                    searchText: $searchText
                )
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: player.currentItem != nil)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isSearchActive)
        }
        .sheet(isPresented: isShowingFullPlayerBinding) {
            FullPlayerView(player: player)
        }
        .alert(
            "Book Completed",
            isPresented: Binding(
                get: { player.bookPendingDeletionPrompt != nil },
                set: { if !$0 { player.bookPendingDeletionPrompt = nil } }
            ),
            presenting: player.bookPendingDeletionPrompt
        ) { item in
            Button("Delete Audio File", role: .destructive) {
                FileImporterService.deletePhysicalFiles(for: item)
                item.isFileOffloaded = true
                item.lastUpdated = Date()
                try? modelContext.save()
                player.bookPendingDeletionPrompt = nil
            }
            Button("Keep File", role: .cancel) {
                player.bookPendingDeletionPrompt = nil
            }
        } message: { item in
            Text("You've finished listening to \"\(item.title)\". Would you like to delete the audio file to free up storage? Your listening history will be preserved.")
        }
    }
}

#Preview {
    MainTabView()
        .environment(AudioPlayerManager())
        .modelContainer(for: LibraryItem.self, inMemory: true)
}
