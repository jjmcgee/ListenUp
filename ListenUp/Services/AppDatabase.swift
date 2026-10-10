import Foundation
import SwiftData

/// Unified SwiftData database provider for ListenUp.
///
/// Ensures a single `ModelContainer` instance is shared across the SwiftUI
/// application lifecycle and the CarPlay template application scene.
public final class AppDatabase: Sendable {
    
    /// Shared singleton instance for production usage.
    public static let shared = AppDatabase()
    
    /// The application's core SwiftData container.
    public let container: ModelContainer
    
    /// Convenient accessor for the main-thread context.
    @MainActor
    public var mainContext: ModelContext {
        container.mainContext
    }
    
    /// Private initializer for production container setup with automatic CloudKit sync.
    private init() {
        let schema = Schema([
            LibraryItem.self
        ])
        do {
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            self.container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            print("[AppDatabase] Warning: CloudKit ModelContainer initialization failed: \(error.localizedDescription). Falling back to local store.")
            do {
                let fallbackConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .none
                )
                self.container = try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                fatalError("Failed to initialize SwiftData ModelContainer: \(error.localizedDescription)")
            }
        }
    }
}
