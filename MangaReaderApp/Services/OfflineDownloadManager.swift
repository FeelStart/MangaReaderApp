import Foundation
import SwiftData
import UIKit

/// Manages offline chapter downloads
/// Handles downloading manga chapter images to permanent local storage
public actor OfflineDownloadManager {
    public static let shared = OfflineDownloadManager()

    private let fileManager = FileManager.default
    private let imageCacheManager = ImageCacheManager.shared
    private var activeDownloads: [UUID: Task<Void, Never>] = [:]

    private init() {}

    // MARK: - Download Directory

    /// Get the base downloads directory
    private var downloadsDirectory: URL {
        get throws {
            let documentsDir = try fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let downloadsDir = documentsDir.appendingPathComponent("Downloads", isDirectory: true)

            if !fileManager.fileExists(atPath: downloadsDir.path) {
                try fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
            }

            return downloadsDir
        }
    }

    /// Get directory for specific manga
    private func mangaDirectory(sourceId: String, mangaId: String) throws -> URL {
        let baseDir = try downloadsDirectory
        let mangaDir = baseDir
            .appendingPathComponent(sourceId, isDirectory: true)
            .appendingPathComponent(mangaId, isDirectory: true)

        if !fileManager.fileExists(atPath: mangaDir.path) {
            try fileManager.createDirectory(at: mangaDir, withIntermediateDirectories: true)
        }

        return mangaDir
    }

    /// Get directory for specific chapter
    private func chapterDirectory(sourceId: String, mangaId: String, chapterId: String) throws -> URL {
        let mangaDir = try mangaDirectory(sourceId: sourceId, mangaId: mangaId)
        let chapterDir = mangaDir.appendingPathComponent(chapterId, isDirectory: true)

        if !fileManager.fileExists(atPath: chapterDir.path) {
            try fileManager.createDirectory(at: chapterDir, withIntermediateDirectories: true)
        }

        return chapterDir
    }

    // MARK: - Download Operations

    /// Start downloading a chapter
    /// - Parameters:
    ///   - task: Download task from SwiftData
    ///   - modelContext: ModelContext for updating progress
    ///   - headers: Optional custom headers (e.g., Referer)
    public func startDownload(
        task: DownloadTask,
        modelContext: ModelContext,
        headers: [String: String]? = nil
    ) {
        // Don't start if already downloading
        guard activeDownloads[task.id] == nil else { return }

        // Create download task
        let downloadTask = Task {
            do {
                // Update status to downloading
                task.status = DownloadStatus.downloading.rawValue
                try modelContext.save()

                // Create chapter directory
                let chapterDir = try chapterDirectory(
                    sourceId: task.sourceId,
                    mangaId: task.mangaId,
                    chapterId: task.chapterId
                )

                let imageURLs = task.imageURLs
                var downloadedCount = 0

                // Download each image
                for (index, imageURL) in imageURLs.enumerated() {
                    // Check if task was cancelled
                    guard !Task.isCancelled else {
                        throw DownloadError.cancelled
                    }

                    // Download image
                    let image = try await imageCacheManager.downloadImage(
                        url: imageURL,
                        headers: headers
                    )

                    // Save to disk
                    let fileName = String(format: "%04d.jpg", index)
                    let fileURL = chapterDir.appendingPathComponent(fileName)

                    if let imageData = image.jpegData(compressionQuality: 0.9) {
                        try imageData.write(to: fileURL)
                    }

                    // Update progress
                    downloadedCount += 1
                    task.updateProgress(downloaded: downloadedCount, total: imageURLs.count)
                    try modelContext.save()
                }

                // Mark as completed
                task.markCompleted()
                try modelContext.save()

                // Save metadata
                try saveChapterMetadata(task: task, chapterDir: chapterDir)

            } catch {
                // Mark as failed
                task.markFailed(error: error.localizedDescription)
                try? modelContext.save()
            }

            // Remove from active downloads
            activeDownloads.removeValue(forKey: task.id)
        }

        activeDownloads[task.id] = downloadTask
    }

    /// Cancel a download
    /// - Parameter taskId: Download task ID
    public func cancelDownload(taskId: UUID) {
        activeDownloads[taskId]?.cancel()
        activeDownloads.removeValue(forKey: taskId)
    }

    /// Pause a download (same as cancel for now)
    public func pauseDownload(taskId: UUID) {
        cancelDownload(taskId: taskId)
    }

    /// Resume a download
    /// - Parameters:
    ///   - task: Download task to resume
    ///   - modelContext: ModelContext for updating
    ///   - headers: Optional custom headers
    public func resumeDownload(
        task: DownloadTask,
        modelContext: ModelContext,
        headers: [String: String]? = nil
    ) {
        // Reset status to pending and restart
        task.status = DownloadStatus.pending.rawValue
        startDownload(task: task, modelContext: modelContext, headers: headers)
    }

    // MARK: - Metadata Management

    private struct ChapterMetadata: Codable {
        let sourceId: String
        let mangaId: String
        let mangaTitle: String
        let chapterId: String
        let chapterTitle: String
        let imageCount: Int
        let downloadedAt: Date
    }

    private func saveChapterMetadata(task: DownloadTask, chapterDir: URL) throws {
        let metadata = ChapterMetadata(
            sourceId: task.sourceId,
            mangaId: task.mangaId,
            mangaTitle: task.mangaTitle,
            chapterId: task.chapterId,
            chapterTitle: task.chapterTitle,
            imageCount: task.totalImages,
            downloadedAt: Date()
        )

        let metadataURL = chapterDir.appendingPathComponent("metadata.json")
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL)
    }

    private func loadChapterMetadata(chapterDir: URL) throws -> ChapterMetadata {
        let metadataURL = chapterDir.appendingPathComponent("metadata.json")
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode(ChapterMetadata.self, from: data)
    }

    // MARK: - Retrieval

    /// Check if chapter is downloaded
    public func isChapterDownloaded(sourceId: String, mangaId: String, chapterId: String) -> Bool {
        guard let chapterDir = try? chapterDirectory(sourceId: sourceId, mangaId: mangaId, chapterId: chapterId) else {
            return false
        }

        let metadataURL = chapterDir.appendingPathComponent("metadata.json")
        return fileManager.fileExists(atPath: metadataURL.path)
    }

    /// Get local image URLs for downloaded chapter
    public func getLocalImageURLs(sourceId: String, mangaId: String, chapterId: String) throws -> [URL] {
        let chapterDir = try chapterDirectory(sourceId: sourceId, mangaId: mangaId, chapterId: chapterId)
        let metadata = try loadChapterMetadata(chapterDir: chapterDir)

        var imageURLs: [URL] = []
        for index in 0..<metadata.imageCount {
            let fileName = String(format: "%04d.jpg", index)
            let fileURL = chapterDir.appendingPathComponent(fileName)
            imageURLs.append(fileURL)
        }

        return imageURLs
    }

    // MARK: - Deletion

    /// Delete downloaded chapter
    public func deleteChapter(sourceId: String, mangaId: String, chapterId: String) throws {
        let chapterDir = try chapterDirectory(sourceId: sourceId, mangaId: mangaId, chapterId: chapterId)
        try fileManager.removeItem(at: chapterDir)
    }

    /// Delete all downloads for a manga
    public func deleteManga(sourceId: String, mangaId: String) throws {
        let mangaDir = try mangaDirectory(sourceId: sourceId, mangaId: mangaId)
        try fileManager.removeItem(at: mangaDir)
    }

    /// Delete all downloads
    public func deleteAllDownloads() throws {
        let downloadsDir = try downloadsDirectory
        try fileManager.removeItem(at: downloadsDir)
        // Recreate the directory
        try fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
    }

    // MARK: - Storage Info

    /// Get total storage used by downloads
    public func getTotalStorageUsed() throws -> UInt64 {
        let downloadsDir = try downloadsDirectory
        return try calculateDirectorySize(url: downloadsDir)
    }

    /// Get storage used by specific manga
    public func getMangaStorageUsed(sourceId: String, mangaId: String) throws -> UInt64 {
        let mangaDir = try mangaDirectory(sourceId: sourceId, mangaId: mangaId)
        return try calculateDirectorySize(url: mangaDir)
    }

    private func calculateDirectorySize(url: URL) throws -> UInt64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var totalSize: UInt64 = 0

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            totalSize += UInt64(resourceValues.fileSize ?? 0)
        }

        return totalSize
    }

    /// Get formatted storage size
    public func getFormattedStorageUsed() throws -> String {
        let size = try getTotalStorageUsed()
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

// MARK: - Download Errors

public enum DownloadError: LocalizedError {
    case cancelled
    case insufficientSpace
    case fileWriteFailed
    case directoryCreationFailed

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "下载已取消"
        case .insufficientSpace:
            return "存储空间不足"
        case .fileWriteFailed:
            return "文件写入失败"
        case .directoryCreationFailed:
            return "目录创建失败"
        }
    }
}

// MARK: - Download Statistics

public struct DownloadStatistics {
    public let totalChapters: Int
    public let totalImages: Int
    public let storageUsed: UInt64
    public let formattedStorage: String

    public init(totalChapters: Int, totalImages: Int, storageUsed: UInt64) {
        self.totalChapters = totalChapters
        self.totalImages = totalImages
        self.storageUsed = storageUsed
        self.formattedStorage = ByteCountFormatter.string(fromByteCount: Int64(storageUsed), countStyle: .file)
    }
}
