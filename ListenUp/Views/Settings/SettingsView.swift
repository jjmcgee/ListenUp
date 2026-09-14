import SwiftUI

/// Settings and preferences screen for ListenUp.
///
/// Configures appearance (Day/Light, Dark, System), playback controls (skip intervals, smart rewind),
/// sleep timer defaults, storage usage, sync status, and application information.
public struct SettingsView: View {
    // MARK: - App Storage Preferences
    
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("skipForwardInterval") private var skipForwardInterval: Double = 30.0
    @AppStorage("skipBackwardInterval") private var skipBackwardInterval: Double = 15.0
    @AppStorage("smartRewindEnabled") private var smartRewindEnabled: Bool = true
    @AppStorage("continuousPlayback") private var continuousPlayback: Bool = true
    @AppStorage("defaultSleepTimerMinutes") private var defaultSleepTimerMinutes: Int = 0
    @AppStorage("shakeToExtendSleepTimer") private var shakeToExtendSleepTimer: Bool = false
    
    @State private var storageUsedString: String = "Calculating..."
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - Appearance (Theme Mode)
                Section {
                    themeModeSelector
                } header: {
                    Text("Appearance")
                } footer: {
                    Text(themeFooterText)
                }
                
                // MARK: - Playback Preferences
                Section {
                    Picker("Skip Forward", selection: $skipForwardInterval) {
                        Text("15 seconds").tag(15.0)
                        Text("30 seconds").tag(30.0)
                        Text("45 seconds").tag(45.0)
                        Text("60 seconds").tag(60.0)
                    }
                    
                    Picker("Skip Backward", selection: $skipBackwardInterval) {
                        Text("10 seconds").tag(10.0)
                        Text("15 seconds").tag(15.0)
                        Text("30 seconds").tag(30.0)
                    }
                    
                    Toggle("Smart Rewind on Resume", isOn: $smartRewindEnabled)
                    
                    Toggle("Continuous Playback", isOn: $continuousPlayback)
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Smart Rewind rewinds 2 seconds when resuming after being paused. Continuous Playback automatically advances to the next chapter or track.")
                }
                
                // MARK: - Sleep Timer Defaults
                Section {
                    Picker("Default Duration", selection: $defaultSleepTimerMinutes) {
                        Text("Off").tag(0)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("45 minutes").tag(45)
                        Text("60 minutes").tag(60)
                    }
                    
                    Toggle("Shake to Extend", isOn: $shakeToExtendSleepTimer)
                } header: {
                    Text("Sleep Timer")
                } footer: {
                    Text("When enabled, gently shaking your device when the sleep timer ends extends playback by 5 minutes.")
                }
                
                // MARK: - Storage & Media Files
                Section {
                    HStack {
                        Label("Audiobook Storage", systemImage: "internaldrive.fill")
                        Spacer()
                        Text(storageUsedString)
                            .foregroundStyle(Color.secondary)
                    }
                } header: {
                    Text("Storage & Documents")
                } footer: {
                    Text("Imported audiobooks and course files are kept locally inside the app sandbox on your device. Audio is never uploaded to external servers.")
                }
                
                // MARK: - Sync & Connected Devices
                Section {
                    HStack {
                        Label("iCloud SwiftData Sync", systemImage: "icloud.fill")
                        Spacer()
                        Text("Active")
                            .foregroundStyle(Color.secondary)
                    }
                    
                    HStack {
                        Label("Apple Watch Connectivity", systemImage: "applewatch")
                        Spacer()
                        Text(WatchSyncManager.shared.isSupported ? "Supported" : "Not Supported")
                            .foregroundStyle(Color.secondary)
                    }
                } header: {
                    Text("Sync & Devices")
                } footer: {
                    Text("Listening positions and chapter completions sync seamlessly across your devices signed into the same Apple Account.")
                }
                
                // MARK: - About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0 (Build 1)")
                            .foregroundStyle(Color.secondary)
                    }
                    
                    HStack {
                        Text("Model")
                        Spacer()
                        Text("Subscription-Free Native Player")
                            .foregroundStyle(Color.secondary)
                    }
                } header: {
                    Text("About ListenUp")
                }
                
                // Extra bottom spacer so form content is never obscured by the floating bottom nav bar
                Section {
                    Color.clear
                        .frame(height: 100)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
            .task {
                calculateStorageUsage()
            }
        }
    }
    
    // MARK: - Theme Selector Subview
    
    private var themeModeSelector: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(AppTheme.allCases) { theme in
                    themeCard(for: theme)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private func themeCard(for theme: AppTheme) -> some View {
        let isSelected = appTheme == theme
        
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                appTheme = theme
            }
        } label: {
            VStack(spacing: 8) {
                // Miniature UI preview card
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(cardBackgroundColor(for: theme))
                    
                    Image(systemName: theme.iconName)
                        .font(.system(size: 24))
                        .foregroundStyle(cardIconColor(for: theme))
                }
                .frame(height: 54)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                }
                
                // Title and checkmark
                HStack(spacing: 4) {
                    Text(theme.rawValue)
                        .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func cardBackgroundColor(for theme: AppTheme) -> Color {
        switch theme {
        case .system:
            return Color.secondary.opacity(0.15)
        case .light:
            return Color.white
        case .dark:
            return Color.black
        }
    }
    
    private func cardIconColor(for theme: AppTheme) -> Color {
        switch theme {
        case .system:
            return Color.accentColor
        case .light:
            return Color.orange
        case .dark:
            return Color.yellow
        }
    }
    
    private var themeFooterText: String {
        switch appTheme {
        case .system:
            return "Matches your device's Light or Dark system appearance automatically."
        case .light:
            return "Always use Light Mode regardless of iOS system settings."
        case .dark:
            return "Always use Dark Mode regardless of iOS system settings."
        }
    }
    
    // MARK: - Storage Calculation
    
    private func calculateStorageUsage() {
        Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                await MainActor.run { storageUsedString = "0 MB" }
                return
            }
            
            var totalBytes: Int64 = 0
            if let enumerator = fileManager.enumerator(
                at: documentsURL,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                       let fileSize = resourceValues.fileSize {
                        totalBytes += Int64(fileSize)
                    }
                }
            }
            
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
            formatter.countStyle = .file
            let formatted = formatter.string(fromByteCount: totalBytes)
            
            await MainActor.run {
                storageUsedString = formatted
            }
        }
    }
}

#Preview {
    SettingsView()
}
