import SwiftUI

/// Blank Profile screen placeholder.
public struct ProfileView: View {
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack {
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if canImport(UIKit)
            .background(Color(uiColor: .systemGroupedBackground))
            #else
            .background(Color.secondary.opacity(0.06))
            #endif
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    ProfileView()
}
