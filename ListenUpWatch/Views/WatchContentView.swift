import SwiftUI

/// Main container view for the ListenUp watchOS application.
/// Paging tab interface navigating between Now Playing (Remote/Local) and the Audiobook Library.
public struct WatchContentView: View {
    @State private var selectedTab: Int = 0
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            WatchNowPlayingView(onNavigateToLibrary: {
                withAnimation {
                    selectedTab = 1
                }
            })
            .tag(0)
            
            NavigationStack {
                WatchLibraryView(onSelectBookToPlay: {
                    withAnimation {
                        selectedTab = 0
                    }
                })
            }
            .tag(1)
            
            NavigationStack {
                WatchDownloadsView()
            }
            .tag(2)
        }
        .tabViewStyle(.verticalPage)
    }
}

#Preview {
    WatchContentView()
        .environment(WatchSyncManager.shared)
        .environment(WatchLibraryStore.shared)
        .environment(WatchAudioPlayerManager.shared)
}
