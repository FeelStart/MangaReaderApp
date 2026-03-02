import Foundation
import SwiftData

/// SwiftData model for manga metadata
/// This is persisted locally for favorites and history
@Model
public final class Manga {
    @Attribute(.unique) public var id: String
    public var sourceId: String
    public var title: String
    public var coverURLString: String?
    public var author: String?
    public var tags: [String]
    public var status: String // "连载中" or "已完结"
    public var latest: String?
    public var updateTime: Date?
    public var mangaDescription: String?

    // Favorites
    public var isFavorite: Bool
    public var favoriteAddedAt: Date?

    // Relationships
    @Relationship(deleteRule: .cascade) public var readingHistory: ReadingHistory?
    @Relationship(deleteRule: .cascade) public var downloadTasks: [DownloadTask]

    public init(id: String, sourceId: String, title: String,
                coverURLString: String? = nil, author: String? = nil,
                tags: [String] = [], status: String = "未知",
                latest: String? = nil, updateTime: Date? = nil,
                description: String? = nil, isFavorite: Bool = false) {
        self.id = id
        self.sourceId = sourceId
        self.title = title
        self.coverURLString = coverURLString
        self.author = author
        self.tags = tags
        self.status = status
        self.latest = latest
        self.updateTime = updateTime
        self.mangaDescription = description
        self.isFavorite = isFavorite
        self.favoriteAddedAt = isFavorite ? Date() : nil
        self.downloadTasks = []
    }

    /// Computed property for cover URL
    public var coverURL: URL? {
        guard let urlString = coverURLString else { return nil }
        return URL(string: urlString)
    }
}

/// SwiftData model for reading history
@Model
public final class ReadingHistory {
    @Attribute(.unique) public var mangaId: String
    public var sourceId: String
    public var title: String
    public var coverURLString: String?

    // Reading progress
    public var lastReadChapterId: String
    public var lastReadChapterTitle: String
    public var lastReadPage: Int
    public var lastReadTime: Date

    // Relationship
    public var manga: Manga?

    public init(mangaId: String, sourceId: String, title: String,
                coverURLString: String? = nil, lastReadChapterId: String,
                lastReadChapterTitle: String, lastReadPage: Int = 0) {
        self.mangaId = mangaId
        self.sourceId = sourceId
        self.title = title
        self.coverURLString = coverURLString
        self.lastReadChapterId = lastReadChapterId
        self.lastReadChapterTitle = lastReadChapterTitle
        self.lastReadPage = lastReadPage
        self.lastReadTime = Date()
    }

    public var coverURL: URL? {
        guard let urlString = coverURLString else { return nil }
        return URL(string: urlString)
    }
}

/// SwiftData model for download tasks
@Model
public final class DownloadTask {
    @Attribute(.unique) public var id: UUID
    public var mangaId: String
    public var mangaTitle: String
    public var chapterId: String
    public var chapterTitle: String
    public var sourceId: String

    // Download status
    public var status: String // "pending", "downloading", "completed", "failed"
    public var progress: Double
    public var totalImages: Int
    public var downloadedImages: Int

    // Image URLs (stored as strings)
    public var imageURLStrings: [String]

    // Timestamps
    public var createdAt: Date
    public var completedAt: Date?
    public var errorMessage: String?

    // Relationship
    public var manga: Manga?

    public init(mangaId: String, mangaTitle: String, chapterId: String,
                chapterTitle: String, sourceId: String, imageURLStrings: [String] = []) {
        self.id = UUID()
        self.mangaId = mangaId
        self.mangaTitle = mangaTitle
        self.chapterId = chapterId
        self.chapterTitle = chapterTitle
        self.sourceId = sourceId
        self.status = "pending"
        self.progress = 0.0
        self.totalImages = imageURLStrings.count
        self.downloadedImages = 0
        self.imageURLStrings = imageURLStrings
        self.createdAt = Date()
    }

    public var imageURLs: [URL] {
        imageURLStrings.compactMap { URL(string: $0) }
    }
}

// MARK: - Download Status Enum

public enum DownloadStatus: String, Codable {
    case pending
    case downloading
    case completed
    case failed

    public var displayName: String {
        switch self {
        case .pending: return "等待中"
        case .downloading: return "下载中"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }
}

// MARK: - Helper Extensions

extension Manga {
    /// Convert to MangaItem for protocol compatibility
    public func toMangaItem() -> MangaItem {
        MangaItem(
            id: id,
            sourceId: sourceId,
            title: title,
            coverURL: coverURL,
            author: author,
            status: MangaStatus(rawValue: status),
            latest: latest,
            updateTime: updateTime
        )
    }

    /// Update from MangaDetail
    public func update(from detail: MangaDetail) {
        self.title = detail.title
        self.coverURLString = detail.coverURL?.absoluteString
        self.author = detail.author
        self.tags = detail.tags
        self.status = detail.status.rawValue
        self.latest = detail.latest
        self.updateTime = detail.updateTime
        self.mangaDescription = detail.description
    }
}

extension ReadingHistory {
    /// Update reading progress
    public func updateProgress(chapterId: String, chapterTitle: String, page: Int) {
        self.lastReadChapterId = chapterId
        self.lastReadChapterTitle = chapterTitle
        self.lastReadPage = page
        self.lastReadTime = Date()
    }
}

extension DownloadTask {
    /// Check if download is active
    public var isActive: Bool {
        status == DownloadStatus.downloading.rawValue
    }

    /// Check if download is completed
    public var isCompleted: Bool {
        status == DownloadStatus.completed.rawValue
    }

    /// Update progress
    public func updateProgress(downloaded: Int, total: Int) {
        self.downloadedImages = downloaded
        self.totalImages = total
        self.progress = total > 0 ? Double(downloaded) / Double(total) : 0.0
    }

    /// Mark as completed
    public func markCompleted() {
        self.status = DownloadStatus.completed.rawValue
        self.progress = 1.0
        self.completedAt = Date()
    }

    /// Mark as failed
    public func markFailed(error: String) {
        self.status = DownloadStatus.failed.rawValue
        self.errorMessage = error
    }
}
