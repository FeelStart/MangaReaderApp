import Foundation
import SwiftUI
import Combine
import Kingfisher

/// ViewModel for manga reader
@MainActor
class ReaderViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var chapter: Chapter?
    @Published var images: [URL] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var currentPage = 0
    @Published var currentChapterIndex = 0
    @Published var chapterTitle: String

    let mangaId: String
    let sourceId: String
    let chapters: [Chapter]

    // Image prefetcher
    private var imagePrefetcher: ImagePrefetcher?
    private let prefetchCount = 10 // Number of images to prefetch ahead

    // MARK: - Initialization

    init(mangaId: String, sourceId: String, chapters: [Chapter], startChapterIndex: Int) {
        self.mangaId = mangaId
        self.sourceId = sourceId
        self.chapters = chapters
        self.currentChapterIndex = startChapterIndex
        self.chapterTitle = chapters[safe: startChapterIndex]?.title ?? ""
    }

    // MARK: - Data Loading

    /// Load chapter images
    func loadChapter() async {
        guard let chapter = chapters[safe: currentChapterIndex] else {
            errorMessage = "章节不存在"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let chapterData = try await SourceRegistry.shared.getChapter(
                mangaId: mangaId,
                chapterId: chapter.id,
                sourceId: sourceId
            )

            self.chapter = chapterData
            images = chapterData.imageURLs
            chapterTitle = chapterData.title

            // Start from first page
            currentPage = 0

            // Prefetch initial images
            prefetchImages(from: 0)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Load next chapter and append images
    func loadNextChapter() async {
        guard hasNextChapter else { return }

        let nextIndex = currentChapterIndex + 1
        guard let nextChapter = chapters[safe: nextIndex] else { return }

        isLoading = true

        do {
            let chapterData = try await SourceRegistry.shared.getChapter(
                mangaId: mangaId,
                chapterId: nextChapter.id,
                sourceId: sourceId
            )

            // Store current image count for prefetch calculation
            let previousImageCount = images.count

            // Append next chapter images to current list
            images.append(contentsOf: chapterData.imageURLs)
            currentChapterIndex = nextIndex
            chapterTitle = chapterData.title

            // Prefetch first images of next chapter
            prefetchImages(from: previousImageCount)
        } catch {
            print("Failed to load next chapter: \(error)")
        }

        isLoading = false
    }

    /// Prefetch images starting from a given index
    func prefetchImages(from startIndex: Int) {
        let endIndex = min(startIndex + prefetchCount, images.count)
        guard startIndex < endIndex else { return }

        let urlsToPrefetch = Array(images[startIndex..<endIndex])

        // Cancel previous prefetch if any
        imagePrefetcher?.stop()

        // Start new prefetch
        imagePrefetcher = ImagePrefetcher(urls: urlsToPrefetch) { skippedResources, failedResources, completedResources in
            print("📥 Prefetched \(completedResources.count) images, skipped \(skippedResources.count), failed \(failedResources.count)")
        }
        imagePrefetcher?.start()
    }

    /// Prefetch images around current page when scrolling
    func updatePrefetchForPage(_ page: Int) {
        // Prefetch images ahead of current page
        let startIndex = page + 1
        prefetchImages(from: startIndex)
    }

    /// Refresh chapter data
    func refresh() async {
        await loadChapter()
    }

    /// Check if there's a next chapter
    var hasNextChapter: Bool {
        currentChapterIndex < chapters.count - 1
    }

    /// Get progress percentage
    var progress: Double {
        guard !images.isEmpty else { return 0 }
        return Double(currentPage + 1) / Double(images.count)
    }

    /// Get progress text
    var progressText: String {
        guard !images.isEmpty else { return "0/0" }
        return "\(currentPage + 1)/\(images.count)"
    }
}

// MARK: - Safe Array Access

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
