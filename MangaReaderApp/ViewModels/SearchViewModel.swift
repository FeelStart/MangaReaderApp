import Foundation
import SwiftUI
import Combine

/// ViewModel for manga search
@MainActor
class SearchViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var searchText = ""
    @Published var searchResults: [MangaItem] = []
    @Published var isSearching = false
    @Published var errorMessage: String?

    @Published var selectedSourceId: String?
    @Published var availableSources: [SourceMetadata] = []

    @Published var currentPage = 1

    // MARK: - Initialization

    init() {
        Task {
            await loadSources()
        }
    }

    // MARK: - Data Loading

    /// Load available manga sources
    func loadSources() async {
        let sources = await SourceRegistry.shared.getSourceMetadata()
        availableSources = sources

        // Select first source by default
        if selectedSourceId == nil, let firstSource = sources.first {
            selectedSourceId = firstSource.id
        }
    }

    /// Perform search
    func search(refresh: Bool = false) async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults.removeAll()
            return
        }

        if refresh {
            currentPage = 1
            searchResults.removeAll()
        }

        isSearching = true
        errorMessage = nil

        do {
            let results = try await SourceRegistry.shared.search(
                keyword: searchText,
                sourceId: selectedSourceId,
                page: currentPage
            )

            if refresh {
                searchResults = results
            } else {
                searchResults.append(contentsOf: results)
            }

            currentPage += 1
        } catch {
            // Print detailed error for debugging
            print("❌ Search Error: \(error)")
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

        isSearching = false
    }

    /// Load more results (pagination)
    func loadMore() async {
        guard !isSearching else { return }
        await search(refresh: false)
    }

    /// Change selected source
    func changeSource(_ sourceId: String) async {
        selectedSourceId = sourceId
        await search(refresh: true)
    }
}
