import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// Interactive sheet allowing users to export a full backup archive of their listening history
/// to an iCloud Drive or Cloud storage directory on device, as well as restore from a previous archive.
public struct ListeningHistoryBackupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [LibraryItem]
    
    @AppStorage("dailyGoalMinutes") private var dailyGoalMinutes: Int = 30
    
    @State private var selectedFormat: BackupArchiveFormat = .json
    @State private var isShowingFileExporter: Bool = false
    @State private var isShowingFileImporter: Bool = false
    
    @State private var exportDocument: ListeningHistoryArchiveDocument?
    @State private var exportFilename: String = "ListenUp-ListeningHistory"
    @State private var exportContentType: UTType = .json
    
    @State private var bannerMessage: String? = nil
    @State private var isErrorMessage: Bool = false
    @State private var isPreparingExport: Bool = false
    
    private let statsStore = ListeningStatsStore.shared
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Banner Notification
                    if let banner = bannerMessage {
                        bannerView(message: banner, isError: isErrorMessage)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // MARK: - History Snapshot Card
                    historySnapshotCard
                    
                    // MARK: - Archive Format Selector Card
                    archiveFormatCard
                    
                    // MARK: - Cloud Export Actions Card
                    cloudExportCard
                    
                    // MARK: - Restore Section Card
                    restoreSectionCard
                    
                    // Bottom clearance
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background {
                LiquidGlassMeshBackground(primaryColor: .accentColor, secondaryColor: .indigo)
            }
            .navigationTitle("Backup Listening History")
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
            #if !os(watchOS)
            .fileExporter(
                isPresented: $isShowingFileExporter,
                document: exportDocument,
                contentType: exportContentType,
                defaultFilename: exportFilename
            ) { result in
                handleExportCompletion(result: result)
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.json, .zip],
                allowsMultipleSelection: false
            ) { result in
                handleImportCompletion(result: result)
            }
            #endif
        }
    }
    
    // MARK: - Banner View
    
    private func bannerView(message: String, isError: Bool) -> some View {
        LiquidGlassCard(cornerRadius: 14, tint: isError ? .red : .green) {
            HStack(spacing: 12) {
                Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isError ? Color.red : Color.green)
                
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.primary)
                
                Spacer()
                
                Button {
                    withAnimation { bannerMessage = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
        }
    }
    
    // MARK: - History Snapshot Card
    
    private var historySnapshotCard: some View {
        let total = statsStore.totalBreakdown(from: allItems)
        let relevantCount = allItems.filter {
            $0.kind != .folder && $0.parent?.kind != .multiPart && ($0.isCompleted || $0.currentPosition > 0)
        }.count
        let recordedDays = statsStore.allDailyRecords.count
        
        return LiquidGlassCard(cornerRadius: 20, tint: .accentColor) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                    
                    Text("Archive Contents")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    
                    Spacer()
                }
                
                Text("This archive contains your complete listening activity, daily streak records, playback positions, and audiobook completions.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                
                Divider().background(Color.secondary.opacity(0.2))
                
                // 3 Metrics Columns
                HStack(spacing: 12) {
                    metricItem(
                        title: "Total Time",
                        value: total.formattedSummary.isEmpty ? "0m" : total.formattedSummary,
                        icon: "headphones"
                    )
                    
                    metricItem(
                        title: "Titles Logged",
                        value: "\(relevantCount)",
                        icon: "books.vertical.fill"
                    )
                    
                    metricItem(
                        title: "Days Logged",
                        value: "\(recordedDays)",
                        icon: "calendar.badge.clock"
                    )
                }
            }
            .padding(16)
        }
    }
    
    private func metricItem(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondary)
            
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    // MARK: - Archive Format Card
    
    private var archiveFormatCard: some View {
        LiquidGlassCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Archive Format")
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                
                Picker("Format", selection: $selectedFormat) {
                    ForEach(BackupArchiveFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                
                Text(selectedFormat.formatDescription)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }
    
    // MARK: - Cloud Export Actions Card
    
    private var cloudExportCard: some View {
        LiquidGlassCard(cornerRadius: 20, tint: .accentColor) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                    
                    Text("Save to Cloud Directory")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    
                    Spacer()
                }
                
                Text("Export the archive file and choose your desired Cloud directory (e.g. iCloud Drive, Google Drive, or OneDrive) or local device storage.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                
                // Primary Action Button: Save to Cloud
                Button {
                    prepareAndTriggerExport()
                } label: {
                    HStack {
                        Spacer()
                        if isPreparingExport {
                            ProgressView()
                                .padding(.trailing, 6)
                        }
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Save Archive to Cloud / Files")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .foregroundStyle(Color.white)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(isPreparingExport)
                
                // Secondary Share Button (Lazy Transferable)
                if selectedFormat == .json {
                    let transferable = JsonBackupArchiveTransferable(archive: currentArchive)
                    ShareLink(
                        item: transferable,
                        preview: SharePreview(transferable.filename, icon: Image(systemName: "doc.text"))
                    ) {
                        shareLinkContent
                    }
                } else {
                    let transferable = ZipBackupArchiveTransferable(archive: currentArchive)
                    ShareLink(
                        item: transferable,
                        preview: SharePreview(transferable.filename, icon: Image(systemName: "doc.zipper"))
                    ) {
                        shareLinkContent
                    }
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - Restore Section Card
    
    private var restoreSectionCard: some View {
        LiquidGlassCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.counterclockwise.icloud.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.indigo)
                    
                    Text("Restore Listening History")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    
                    Spacer()
                }
                
                Text("Select an existing archive file (.json or .zip) from your Cloud directory or Files to restore your listening streaks, completion dates, and audiobook progress.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                
                Button {
                    isShowingFileImporter = true
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 15))
                        Text("Restore from Cloud Backup...")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .foregroundStyle(Color.primary)
                    .background(Color.secondary.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }
    
    // MARK: - Export Logic
    
    private var shareLinkContent: some View {
        HStack {
            Spacer()
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15))
            Text("Share Archive via AirDrop / Mail")
                .font(.system(size: 14, weight: .medium))
            Spacer()
        }
        .padding(.vertical, 11)
        .foregroundStyle(Color.primary)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var currentArchive: ListeningHistoryArchive {
        ListeningHistoryBackupService.buildArchive(
            items: allItems,
            dailyGoalMinutes: dailyGoalMinutes
        )
    }
    
    private func prepareAndTriggerExport() {
        isPreparingExport = true
        let format = selectedFormat
        let archive = currentArchive
        
        Task.detached(priority: .userInitiated) {
            do {
                let payload = try ListeningHistoryBackupService.createExportPayload(
                    format: format,
                    archive: archive
                )
                
                await MainActor.run {
                    self.exportDocument = ListeningHistoryArchiveDocument(
                        data: payload.data,
                        contentType: payload.contentType
                    )
                    self.exportFilename = payload.filename
                    self.exportContentType = payload.contentType
                    self.isPreparingExport = false
                    self.isShowingFileExporter = true
                }
            } catch {
                await MainActor.run {
                    self.isPreparingExport = false
                    self.bannerMessage = "Failed to create archive: \(error.localizedDescription)"
                    self.isErrorMessage = true
                }
            }
        }
    }
    
    private func handleExportCompletion(result: Result<URL, any Error>) {
        switch result {
        case .success(let destinationURL):
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            withAnimation {
                bannerMessage = "Archive saved successfully to \(destinationURL.lastPathComponent)!"
                isErrorMessage = false
            }
        case .failure(let error):
            withAnimation {
                bannerMessage = "Export was canceled or failed: \(error.localizedDescription)"
                isErrorMessage = true
            }
        }
    }
    
    // MARK: - Import Logic
    
    private func handleImportCompletion(result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let sourceURL = urls.first else { return }
            guard sourceURL.startAccessingSecurityScopedResource() else {
                withAnimation {
                    bannerMessage = "Access denied to selected archive file."
                    isErrorMessage = true
                }
                return
            }
            defer {
                sourceURL.stopAccessingSecurityScopedResource()
            }
            
            do {
                let fileData = try Data(contentsOf: sourceURL)
                let archive = try ListeningHistoryBackupService.parseArchive(from: fileData)
                let restoreResult = ListeningHistoryBackupService.restore(from: archive, into: modelContext)
                
                #if canImport(UIKit)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
                withAnimation {
                    bannerMessage = restoreResult.summaryMessage
                    isErrorMessage = false
                }
            } catch {
                withAnimation {
                    bannerMessage = "Failed to parse archive: \(error.localizedDescription)"
                    isErrorMessage = true
                }
            }
            
        case .failure(let error):
            withAnimation {
                bannerMessage = "Failed to select file: \(error.localizedDescription)"
                isErrorMessage = true
            }
        }
    }
}

#Preview {
    ListeningHistoryBackupSheet()
        .modelContainer(for: LibraryItem.self, inMemory: true)
}
