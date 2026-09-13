import SwiftUI

/// Blank Settings screen placeholder.
public struct SettingsView: View {
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
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
