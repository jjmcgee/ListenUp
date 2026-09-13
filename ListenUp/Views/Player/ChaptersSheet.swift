import SwiftUI

/// Presentation sheet displaying the list of chapters for the active audiobook.
/// Matches the design from the reference screenshot:
/// - Leading circular close ('xmark') button.
/// - Centered "Chapters" title.
/// - Trailing bordered "Reload" pill button.
/// - Plain-style list with chapter title, formatted "Start: HH:mm:ss - Duration: mm:ss",
///   and a checkmark on the currently active chapter.
public struct ChaptersSheet: View {
    @Environment(\.dismiss) private var dismiss
    var player: AudioPlayerManager
    
    public init(player: AudioPlayerManager) {
        self.player = player
    }
    
    public var body: some View {
        NavigationStack {
            Group {
                if player.isLoadingChapters {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading chapters…")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if player.chapters.isEmpty {
                    ContentUnavailableView {
                        Label("No Chapters Found", systemImage: "book.pages")
                    } description: {
                        Text("This audiobook does not contain embedded chapter markers.")
                    } actions: {
                        Button {
                            player.reloadChapters()
                        } label: {
                            Text("Try Reloading")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(player.chapters) { chapter in
                                Button {
                                    player.skipToChapter(chapter)
                                    dismiss()
                                } label: {
                                    HStack(alignment: .center, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(chapter.title)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(Color.primary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            
                                            Text("Start: \(TimeFormatting.formatChapterTimestamp(chapter.startTime)) - Duration: \(TimeFormatting.formatChapterDuration(chapter.duration))")
                                                .font(.system(size: 13, weight: .regular))
                                                .foregroundStyle(Color.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if player.currentChapter?.id == chapter.id {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .id(chapter.id)
                            }
                        }
                        .listStyle(.plain)
                        .onAppear {
                            if let currentId = player.currentChapter?.id {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    proxy.scrollTo(currentId, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chapters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                if player.chapters.isEmpty && !player.isLoadingChapters {
                    player.reloadChapters()
                }
            }
            .toolbar {
                // Leading circular 'X' dismiss button
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Close")
                }
                
                // Trailing bordered "Reload" pill button
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        player.reloadChapters()
                    } label: {
                        Text("Reload")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .overlay(
                                Capsule()
                                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .disabled(player.isLoadingChapters)
                    .accessibilityLabel("Reload Chapters")
                }
            }
        }
    }
}

#Preview("Chapters Sheet") {
    ChaptersSheet(player: .previewMock())
}

