import Foundation
import SwiftData

/// SwiftData model container configuration
public actor ModelContainerProvider {
    public static let shared = ModelContainerProvider()

    private var _container: ModelContainer?

    private init() {}

    /// Get or create the model container
    public func container() throws -> ModelContainer {
        if let container = _container {
            return container
        }

        let schema = Schema([
            Manga.self,
            ReadingHistory.self,
            DownloadTask.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        let container = try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )

        _container = container
        return container
    }

    /// Create in-memory container for testing
    public func createInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Manga.self,
            ReadingHistory.self,
            DownloadTask.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        return try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
    }

    /// Reset the container (useful for testing)
    public func reset() {
        _container = nil
    }
}

// MARK: - Model Context Helper

extension ModelContext {
    /// Fetch all favorites
    public func fetchFavorites() throws -> [Manga] {
        let descriptor = FetchDescriptor<Manga>(
            predicate: #Predicate { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.favoriteAddedAt, order: .reverse)]
        )
        return try fetch(descriptor)
    }

    /// Fetch reading history, ordered by most recent
    public func fetchReadingHistory(limit: Int? = nil) throws -> [ReadingHistory] {
        var descriptor = FetchDescriptor<ReadingHistory>(
            sortBy: [SortDescriptor(\.lastReadTime, order: .reverse)]
        )
        if let limit = limit {
            descriptor.fetchLimit = limit
        }
        return try fetch(descriptor)
    }

    /// Fetch active download tasks
    public func fetchActiveDownloads() throws -> [DownloadTask] {
        let descriptor = FetchDescriptor<DownloadTask>(
            predicate: #Predicate {
                $0.status == "downloading" || $0.status == "pending"
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try fetch(descriptor)
    }

    /// Fetch completed downloads
    public func fetchCompletedDownloads() throws -> [DownloadTask] {
        let descriptor = FetchDescriptor<DownloadTask>(
            predicate: #Predicate { $0.status == "completed" },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        return try fetch(descriptor)
    }

    /// Find manga by ID and source
    public func findManga(id: String, sourceId: String) throws -> Manga? {
        let descriptor = FetchDescriptor<Manga>(
            predicate: #Predicate { $0.id == id && $0.sourceId == sourceId }
        )
        return try fetch(descriptor).first
    }

    /// Find or create manga
    public func findOrCreateManga(id: String, sourceId: String, title: String) throws -> Manga {
        if let existing = try findManga(id: id, sourceId: sourceId) {
            return existing
        }

        let manga = Manga(id: id, sourceId: sourceId, title: title)
        insert(manga)
        return manga
    }

    /// Find reading history for manga
    public func findReadingHistory(mangaId: String) throws -> ReadingHistory? {
        let descriptor = FetchDescriptor<ReadingHistory>(
            predicate: #Predicate { $0.mangaId == mangaId }
        )
        return try fetch(descriptor).first
    }

    /// Update or create reading history
    public func updateReadingHistory(
        mangaId: String,
        sourceId: String,
        title: String,
        coverURLString: String?,
        chapterId: String,
        chapterTitle: String,
        page: Int
    ) throws {
        if let existing = try findReadingHistory(mangaId: mangaId) {
            existing.updateProgress(
                chapterId: chapterId,
                chapterTitle: chapterTitle,
                page: page
            )
        } else {
            let history = ReadingHistory(
                mangaId: mangaId,
                sourceId: sourceId,
                title: title,
                coverURLString: coverURLString,
                lastReadChapterId: chapterId,
                lastReadChapterTitle: chapterTitle,
                lastReadPage: page
            )
            insert(history)
        }
        try save()
    }

    /// Toggle favorite status
    public func toggleFavorite(manga: Manga) throws {
        manga.isFavorite.toggle()
        manga.favoriteAddedAt = manga.isFavorite ? Date() : nil
        try save()
    }

    /// Clear all reading history
    public func clearReadingHistory() throws {
        let allHistory = try fetchReadingHistory()
        for history in allHistory {
            delete(history)
        }
        try save()
    }

    /// Delete download task
    public func deleteDownload(_ task: DownloadTask) throws {
        delete(task)
        try save()
    }

    /// Get database statistics
    public func getDatabaseStats() throws -> DatabaseStats {
        let favoritesCount = try fetchFavorites().count
        let historyCount = try fetchReadingHistory().count
        let downloadsCount = try fetchCompletedDownloads().count

        return DatabaseStats(
            favoritesCount: favoritesCount,
            historyCount: historyCount,
            downloadsCount: downloadsCount
        )
    }
}

// MARK: - Database Stats

public struct DatabaseStats {
    public let favoritesCount: Int
    public let historyCount: Int
    public let downloadsCount: Int

    public init(favoritesCount: Int, historyCount: Int, downloadsCount: Int) {
        self.favoritesCount = favoritesCount
        self.historyCount = historyCount
        self.downloadsCount = downloadsCount
    }
}
