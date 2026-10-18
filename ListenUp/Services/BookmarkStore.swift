import Foundation
import SwiftUI

/// Observable store for creating, updating, deleting, and persisting user bookmarks.
@Observable
@MainActor
public final class BookmarkStore {
    
    public static let shared = BookmarkStore()
    
    private let userDefaultsKey = "listenup_user_bookmarks_v1"
    private var bookmarksByBookID: [UUID: [UserBookmark]] = [:]
    
    public init() {
        loadBookmarks()
    }
    
    public func bookmarks(for bookID: UUID) -> [UserBookmark] {
        return bookmarksByBookID[bookID] ?? []
    }
    
    @discardableResult
    public func addBookmark(bookID: UUID, title: String? = nil, timestamp: Double) -> UserBookmark {
        var list = bookmarksByBookID[bookID] ?? []
        let count = list.count + 1
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle: String
        if let trimmed = trimmedTitle, !trimmed.isEmpty {
            resolvedTitle = trimmed
        } else {
            resolvedTitle = "Bookmark \(count)"
        }
        
        let newBookmark = UserBookmark(
            bookID: bookID,
            title: resolvedTitle,
            timestamp: max(0, timestamp)
        )
        
        list.append(newBookmark)
        list.sort { $0.timestamp < $1.timestamp }
        bookmarksByBookID[bookID] = list
        saveBookmarks()
        return newBookmark
    }
    
    public func updateBookmarkTitle(bookmarkID: UUID, bookID: UUID, newTitle: String) {
        guard var list = bookmarksByBookID[bookID],
              let index = list.firstIndex(where: { $0.id == bookmarkID }) else {
            return
        }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        list[index].title = trimmed
        bookmarksByBookID[bookID] = list
        saveBookmarks()
    }
    
    public func deleteBookmark(bookmarkID: UUID, bookID: UUID) {
        guard var list = bookmarksByBookID[bookID] else { return }
        list.removeAll { $0.id == bookmarkID }
        bookmarksByBookID[bookID] = list
        saveBookmarks()
    }
    
    public func deleteBookmarks(for bookID: UUID, at offsets: IndexSet) {
        guard var list = bookmarksByBookID[bookID] else { return }
        list.remove(atOffsets: offsets)
        bookmarksByBookID[bookID] = list
        saveBookmarks()
    }
    
    public func reset() {
        bookmarksByBookID.removeAll()
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
    
    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([UUID: [UserBookmark]].self, from: data)
            self.bookmarksByBookID = decoded
        } catch {
            print("[BookmarkStore] Failed to decode bookmarks: \(error)")
        }
    }
    
    private func saveBookmarks() {
        do {
            let encoded = try JSONEncoder().encode(bookmarksByBookID)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        } catch {
            print("[BookmarkStore] Failed to encode bookmarks: \(error)")
        }
    }
}
