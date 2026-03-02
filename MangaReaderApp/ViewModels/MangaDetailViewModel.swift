import Foundation
import SwiftUI
import Combine

/// ViewModel for manga detail
@MainActor
class MangaDetailViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var mangaDetail: MangaDetail?
    @Published private var rawChapters: [Chapter] = []
    @Published var isChaptersReversed = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    let mangaId: String
    let sourceId: String

    /// Computed chapters with sorting applied
    var chapters: [Chapter] {
        isChaptersReversed ? rawChapters.reversed() : rawChapters
    }

    // MARK: - Initialization

    init(mangaId: String, sourceId: String) {
        self.mangaId = mangaId
        self.sourceId = sourceId
    }

    // MARK: - Private Methods

    /// Deduplicate chapters by ID while preserving order
    private func deduplicateChapters(_ chapters: [Chapter]) -> [Chapter] {
        var seen = Set<String>()
        var uniqueChapters: [Chapter] = []

        for chapter in chapters {
            if !seen.contains(chapter.id) {
                seen.insert(chapter.id)
                uniqueChapters.append(chapter)
            }
        }

        return uniqueChapters
    }

    // MARK: - Data Loading

    /// Load manga detail information
    func loadMangaInfo() async {
        isLoading = true
        errorMessage = nil

        do {
            let detail = try await SourceRegistry.shared.getMangaInfo(
                mangaId: mangaId,
                sourceId: sourceId
            )

            mangaDetail = detail
            rawChapters = deduplicateChapters(detail.chapters ?? [])

            // If chapters are not included, fetch them separately
            if rawChapters.isEmpty {
                await loadChapterList()
            }
        } catch {
            // Print detailed error for debugging
            print("❌ Load Manga Info Error: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .dataCorrupted(let context):
                    print("Data corrupted: \(context)")
                case .keyNotFound(let key, let context):
                    print("Key '\(key)' not found: \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    print("Type '\(type)' mismatch: \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("Value '\(type)' not found: \(context.debugDescription)")
                @unknown default:
                    print("Unknown decoding error")
                }
            }
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Load chapter list (if not included in manga info)
    func loadChapterList() async {
        do {
            if let chapterList = try await SourceRegistry.shared.getChapterList(
                mangaId: mangaId,
                sourceId: sourceId
            ) {
                rawChapters = deduplicateChapters(chapterList)
            }
        } catch {
            // Chapter list errors are not critical if we already have manga info
            print("Failed to load chapter list: \(error)")
        }
    }

    /// Refresh all data
    func refresh() async {
        await loadMangaInfo()
    }
}
