import SwiftUI

/// Supported application visual themes for ListenUp.
public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light (Day)"
        case .dark: return "Dark"
        }
    }
    
    public var iconName: String {
        switch self {
        case .system: return "circle.righthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
