import Foundation
import SwiftUI
import SwiftData

/// ViewModel for reading history
@MainActor
class HistoryViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var historyItems: [ReadingHistory] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let modelContext: ModelContext

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Data Loading

    /// Load all reading history, sorted by last read time
    func loadHistory() {
        isLoading = true
        errorMessage = nil

        do {
            let descriptor = FetchDescriptor<ReadingHistory>(
                sortBy: [SortDescriptor(\.lastReadTime, order: .reverse)]
            )
            historyItems = try modelContext.fetch(descriptor)
        } catch {
            errorMessage = "加载历史失败: \(error.localizedDescription)"
            print("❌ Failed to load history: \(error)")
        }

        isLoading = false
    }

    /// Delete a history item
    func deleteHistory(_ history: ReadingHistory) {
        modelContext.delete(history)

        do {
            try modelContext.save()
            loadHistory()
        } catch {
            errorMessage = "删除失败: \(error.localizedDescription)"
            print("❌ Failed to delete history: \(error)")
        }
    }

    /// Clear all history
    func clearAllHistory() {
        do {
            // Delete all reading history
            try modelContext.delete(model: ReadingHistory.self)
            try modelContext.save()

            historyItems = []
        } catch {
            errorMessage = "清空失败: \(error.localizedDescription)"
            print("❌ Failed to clear history: \(error)")
        }
    }

    /// Save or update reading progress
    static func saveReadingProgress(
        modelContext: ModelContext,
        mangaId: String,
        sourceId: String,
        title: String,
        coverURL: URL?,
        chapterId: String,
        chapterTitle: String,
        page: Int
    ) {
        do {
            // Check if history already exists
            let descriptor = FetchDescriptor<ReadingHistory>(
                predicate: #Predicate { $0.mangaId == mangaId && $0.sourceId == sourceId }
            )

            let existingHistory = try modelContext.fetch(descriptor).first

            if let history = existingHistory {
                // Update existing history
                history.updateProgress(chapterId: chapterId, chapterTitle: chapterTitle, page: page)
            } else {
                // Create new history
                let newHistory = ReadingHistory(
                    mangaId: mangaId,
                    sourceId: sourceId,
                    title: title,
                    coverURLString: coverURL?.absoluteString,
                    lastReadChapterId: chapterId,
                    lastReadChapterTitle: chapterTitle,
                    lastReadPage: page
                )
                modelContext.insert(newHistory)
            }

            try modelContext.save()
            print("✅ Saved reading progress: \(title) - \(chapterTitle) - page \(page)")
        } catch {
            print("❌ Failed to save reading progress: \(error)")
        }
    }

    /// Get reading history for a specific manga
    static func getReadingHistory(
        modelContext: ModelContext,
        mangaId: String,
        sourceId: String
    ) -> ReadingHistory? {
        do {
            let descriptor = FetchDescriptor<ReadingHistory>(
                predicate: #Predicate { $0.mangaId == mangaId && $0.sourceId == sourceId }
            )
            return try modelContext.fetch(descriptor).first
        } catch {
            print("❌ Failed to get reading history: \(error)")
            return nil
        }
    }
}
