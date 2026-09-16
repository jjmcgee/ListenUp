import SwiftUI

/// Presentation sheet allowing users to set or cancel an audio sleep timer.
public struct SleepTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var player: AudioPlayerManager
    
    private let options: [SleepTimerOption] = [
        .off,
        .minutes(5),
        .minutes(15),
        .minutes(30),
        .minutes(45),
        .minutes(60),
        .endOfChapter
    ]
    
    public init(player: AudioPlayerManager) {
        self.player = player
    }
    
    public var body: some View {
        NavigationStack {
            List {
                if let remaining = player.sleepTimerRemaining, player.activeSleepTimerOption != .off {
                    Section {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.18))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "timer")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            
                            Text("Active Timer")
                                .font(.headline)
                            
                            Spacer()
                            
                            Text(TimeFormatting.formatTimestamp(remaining))
                                .font(.system(.title3, design: .monospaced, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
                }
                
                Section("Select Duration") {
                    ForEach(options) { option in
                        Button {
                            player.setSleepTimer(option)
                            dismiss()
                        } label: {
                            HStack {
                                Text(option.title)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                if isSelected(option) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sleep Timer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func isSelected(_ option: SleepTimerOption) -> Bool {
        switch (option, player.activeSleepTimerOption) {
        case (.off, .off):
            return true
        case (.minutes(let m1), .minutes(let m2)):
            return m1 == m2
        case (.endOfChapter, .endOfChapter):
            return true
        default:
            return false
        }
    }
}
