import SwiftUI

/// Available root navigation tabs in ListenUp.
public enum NavTab: String, CaseIterable, Identifiable, Sendable {
    case library = "Library"
    case profile = "Profile"
    case settings = "Settings"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .library: return "books.vertical.fill"
        case .profile: return "person.crop.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Floating glass-morphic bottom navigation bar.
///
/// Supports smooth morphing animation between two states:
/// 1. Default (Image 1):
///    - Left: Wide 3-tab capsule (Library, Profile, Settings).
///    - Right: Circular search button.
/// 2. Search Mode (Image 2):
///    - Left: 3 tabs shrink into a circular button with the Library icon. Tapping it expands the tabs back and shrinks search.
///    - Right: Search button expands into a wide search bar capsule. Keyboard only displays when tapped inside the search field.
public struct FloatingNavBar: View {
    @Binding public var selectedTab: NavTab
    @Binding public var isSearchActive: Bool
    @Binding public var searchText: String
    
    @FocusState private var isSearchFieldFocused: Bool
    
    private let barHeight: CGFloat = 64
    private let circleSize: CGFloat = 64
    
    public init(
        selectedTab: Binding<NavTab>,
        isSearchActive: Binding<Bool>,
        searchText: Binding<String>
    ) {
        self._selectedTab = selectedTab
        self._isSearchActive = isSearchActive
        self._searchText = searchText
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // MARK: - Left Element (Morphs between 3 Tabs Capsule and Circular Library Icon)
            ZStack {
                if !isSearchActive {
                    // Wide 3-tab row
                    HStack(spacing: 4) {
                        ForEach(NavTab.allCases) { tab in
                            tabButton(for: tab)
                        }
                    }
                    .padding(.horizontal, 6)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                        removal: .opacity.combined(with: .scale(scale: 0.9))
                    ))
                } else {
                    // Collapsed Circular Library Icon (tap to expand the 3 tabs and shrink search)
                    Button {
                        toggleSearch(active: false)
                    } label: {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: circleSize, height: circleSize)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                        removal: .opacity.combined(with: .scale(scale: 0.9))
                    ))
                }
            }
            .frame(maxWidth: isSearchActive ? circleSize : .infinity)
            .frame(height: barHeight)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
            }
            .overlay {
                Capsule()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            
            // MARK: - Right Element (Morphs between Circular Search Button and Wide Search Bar)
            ZStack {
                if !isSearchActive {
                    // Circular search trigger button
                    Button {
                        toggleSearch(active: true)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: circleSize, height: circleSize)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                        removal: .opacity.combined(with: .scale(scale: 0.9))
                    ))
                } else {
                    // Expanded Search Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.7))
                            .padding(.leading, 18)
                        
                        #if os(iOS)
                        TextField("Search Library", text: $searchText)
                            .font(.system(size: 17, weight: .regular))
                            .focused($isSearchFieldFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .submitLabel(.search)
                        #else
                        TextField("Search Library", text: $searchText)
                            .font(.system(size: 17, weight: .regular))
                            .focused($isSearchFieldFocused)
                            .autocorrectionDisabled(true)
                        #endif
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.secondary)
                            }
                            .padding(.trailing, 14)
                        } else {
                            Spacer()
                                .frame(width: 14)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                        removal: .opacity.combined(with: .scale(scale: 0.9))
                    ))
                }
            }
            .frame(maxWidth: isSearchActive ? .infinity : circleSize)
            .frame(height: barHeight)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
            }
            .overlay {
                Capsule()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }
    
    // MARK: - Tab Button Subview
    
    @ViewBuilder
    private func tabButton(for tab: NavTab) -> some View {
        let isSelected = selectedTab == tab
        
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helpers
    
    private func toggleSearch(active: Bool) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            isSearchActive = active
            if !active {
                isSearchFieldFocused = false
                searchText = ""
            }
        }
        // Keyboard does NOT automatically open; opens when user taps into the expanded search box.
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.15).ignoresSafeArea()
        
        FloatingNavBar(
            selectedTab: .constant(.library),
            isSearchActive: .constant(false),
            searchText: .constant("")
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
