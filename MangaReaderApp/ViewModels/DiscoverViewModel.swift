import Foundation
import SwiftUI
import Combine

/// ViewModel for manga discover/browsing
@MainActor
class DiscoverViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var mangaList: [MangaItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var selectedSourceId: String?
    @Published var availableSources: [SourceMetadata] = []

    @Published var currentPage = 1
    @Published var filters: [String: Any] = [:]

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

    /// Perform discovery with current filters
    func discover(refresh: Bool = false) async {
        if refresh {
            currentPage = 1
            mangaList.removeAll()
        }

        isLoading = true
        errorMessage = nil

        do {
            let results = try await SourceRegistry.shared.discover(
                sourceId: selectedSourceId,
                page: currentPage,
                filters: filters
            )

            if refresh {
                mangaList = results
            } else {
                mangaList.append(contentsOf: results)
            }

            currentPage += 1
        } catch {
            // Print detailed error for debugging
            print("❌ Discover Error: \(error)")
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

    /// Load more manga (pagination)
    func loadMore() async {
        guard !isLoading else { return }
        await discover(refresh: false)
    }

    /// Change selected source
    func changeSource(_ sourceId: String) async {
        selectedSourceId = sourceId
        filters.removeAll()
        await discover(refresh: true)
    }

    /// Update filter and refresh
    func updateFilter(key: String, value: Any) async {
        filters[key] = value
        await discover(refresh: true)
    }
}
