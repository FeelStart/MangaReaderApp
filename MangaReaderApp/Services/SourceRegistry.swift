import Foundation

/// Central registry for all manga sources
/// Provides discovery, search, and source management capabilities
public actor SourceRegistry {
    // MARK: - Singleton

    public static let shared = SourceRegistry()

    // MARK: - Properties

    /// All registered sources, indexed by source ID
    private var sources: [String: MangaSourceProtocol] = [:]

    /// Source initialization order (for UI display)
    private var sourceOrder: [String] = []

    // MARK: - Initialization

    private init() {
        registerDefaultSources()
    }

    // MARK: - Source Registration

    /// Register all default manga sources
    private func registerDefaultSources() {
        // Tier 1: JSON API sources (easiest to implement)
        // register(source: DMZJSource())  // Disabled: TLS certificate issues
        register(source: COPYSource())
        register(source: BZMSource())

        // TODO: Register additional sources
        // register(source: MHRSource())
        // register(source: DMWSource())
        // register(source: MHGSource())
    }

    /// Register a new manga source
    /// - Parameter source: Source to register
    public func register(source: MangaSourceProtocol) {
        sources[source.id] = source
        if !sourceOrder.contains(source.id) {
            sourceOrder.append(source.id)
        }
    }

    /// Unregister a manga source
    /// - Parameter sourceId: Source ID to remove
    public func unregister(sourceId: String) {
        sources.removeValue(forKey: sourceId)
        sourceOrder.removeAll { $0 == sourceId }
    }

    // MARK: - Source Access

    /// Get a specific manga source by ID
    /// - Parameter sourceId: Source identifier
    /// - Returns: The manga source, or nil if not found
    public func getSource(id sourceId: String) -> MangaSourceProtocol? {
        return sources[sourceId]
    }

    /// Get all registered sources
    /// - Returns: Array of all sources in registration order
    public func getAllSources() -> [MangaSourceProtocol] {
        return sourceOrder.compactMap { sources[$0] }
    }

    /// Get all source IDs
    /// - Returns: Array of source IDs in registration order
    public func getAllSourceIds() -> [String] {
        return sourceOrder
    }

    /// Get source metadata for UI display
    /// - Returns: Array of source metadata
    public func getSourceMetadata() -> [SourceMetadata] {
        return sourceOrder.compactMap { sourceId in
            guard let source = sources[sourceId] else { return nil }
            return SourceMetadata(
                id: source.id,
                name: source.name,
                baseURL: source.baseURL.absoluteString
            )
        }
    }

    // MARK: - Discovery & Search

    /// Perform discovery across all sources or a specific source
    /// - Parameters:
    ///   - sourceId: Optional specific source ID. If nil, searches all sources.
    ///   - page: Page number (1-indexed)
    ///   - filters: Filter parameters
    /// - Returns: Array of manga items
    public func discover(
        sourceId: String? = nil,
        page: Int = 1,
        filters: [String: Any] = [:]
    ) async throws -> [MangaItem] {
        if let sourceId = sourceId {
            // Discovery from specific source
            guard let source = sources[sourceId] else {
                throw RegistryError.sourceNotFound(sourceId)
            }

            print("🔍 [SourceRegistry] Discovering from source: \(source.name) (ID: \(sourceId))")
            print("   Page: \(page), Filters: \(filters)")

            let request = source.prepareDiscoveryRequest(page: page, filters: filters)
            print("   Request URL: \(request.url?.absoluteString ?? "nil")")
            print("   Request Method: \(request.httpMethod ?? "GET")")
            if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
                print("   Request Body: \(bodyString)")
            }

            let data = try await NetworkService.shared.request(request)
            print("   Response size: \(data.count) bytes")

            let items = try await source.handleDiscovery(response: data)
            print("   ✅ Parsed \(items.count) items successfully")
            return items
        } else {
            // Discovery from all sources (parallel)
            let allSources = getAllSources()

            let results = try await withThrowingTaskGroup(of: [MangaItem].self) { group in
                for source in allSources {
                    group.addTask {
                        let request = source.prepareDiscoveryRequest(page: page, filters: filters)
                        let data = try await NetworkService.shared.request(request)
                        return try await source.handleDiscovery(response: data)
                    }
                }

                var allItems: [MangaItem] = []
                for try await items in group {
                    allItems.append(contentsOf: items)
                }
                return allItems
            }

            return results
        }
    }

    /// Search across all sources or a specific source
    /// - Parameters:
    ///   - keyword: Search query
    ///   - sourceId: Optional specific source ID. If nil, searches all sources.
    ///   - page: Page number (1-indexed)
    /// - Returns: Array of manga items
    public func search(
        keyword: String,
        sourceId: String? = nil,
        page: Int = 1
    ) async throws -> [MangaItem] {
        if let sourceId = sourceId {
            // Search in specific source
            guard let source = sources[sourceId] else {
                throw RegistryError.sourceNotFound(sourceId)
            }

            let request = source.prepareSearchRequest(keyword: keyword, page: page)
            let data = try await NetworkService.shared.request(request)
            return try await source.handleSearch(response: data)
        } else {
            // Search in all sources (parallel)
            let allSources = getAllSources()

            let results = try await withThrowingTaskGroup(of: [MangaItem].self) { group in
                for source in allSources {
                    group.addTask {
                        let request = source.prepareSearchRequest(keyword: keyword, page: page)
                        let data = try await NetworkService.shared.request(request)
                        return try await source.handleSearch(response: data)
                    }
                }

                var allItems: [MangaItem] = []
                for try await items in group {
                    allItems.append(contentsOf: items)
                }
                return allItems
            }

            return results
        }
    }

    // MARK: - Manga Info & Chapters

    /// Fetch detailed manga information
    /// - Parameters:
    ///   - mangaId: Manga identifier
    ///   - sourceId: Source identifier
    /// - Returns: Detailed manga information
    public func getMangaInfo(mangaId: String, sourceId: String) async throws -> MangaDetail {
        guard let source = sources[sourceId] else {
            throw RegistryError.sourceNotFound(sourceId)
        }

        let request = source.prepareMangaInfoRequest(mangaId: mangaId)
        let data = try await NetworkService.shared.request(request)
        return try await source.handleMangaInfo(response: data, mangaId: mangaId)
    }

    /// Fetch chapter list (if not included in manga info)
    /// - Parameters:
    ///   - mangaId: Manga identifier
    ///   - sourceId: Source identifier
    ///   - page: Optional page number for paginated chapter lists
    /// - Returns: Array of chapters, or nil if chapters are in manga info
    public func getChapterList(
        mangaId: String,
        sourceId: String,
        page: Int? = nil
    ) async throws -> [Chapter]? {
        guard let source = sources[sourceId] else {
            throw RegistryError.sourceNotFound(sourceId)
        }

        guard let request = source.prepareChapterListRequest(mangaId: mangaId, page: page) else {
            // Chapters are included in manga info, return nil
            return nil
        }

        let data = try await NetworkService.shared.request(request)
        return try await source.handleChapterList(response: data, mangaId: mangaId)
    }

    /// Fetch chapter images
    /// - Parameters:
    ///   - mangaId: Manga identifier
    ///   - chapterId: Chapter identifier
    ///   - sourceId: Source identifier
    /// - Returns: Chapter with image URLs
    public func getChapter(
        mangaId: String,
        chapterId: String,
        sourceId: String
    ) async throws -> Chapter {
        guard let source = sources[sourceId] else {
            throw RegistryError.sourceNotFound(sourceId)
        }

        let request = source.prepareChapterRequest(mangaId: mangaId, chapterId: chapterId)
        let data = try await NetworkService.shared.request(request)
        return try await source.handleChapter(response: data, mangaId: mangaId, chapterId: chapterId)
    }
}

// MARK: - Supporting Types

/// Metadata for displaying source information
public struct SourceMetadata: Identifiable, Codable {
    public let id: String
    public let name: String
    public let baseURL: String

    public init(id: String, name: String, baseURL: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }
}

/// Registry-specific errors
public enum RegistryError: LocalizedError {
    case sourceNotFound(String)
    case multiSourceError([Error])

    public var errorDescription: String? {
        switch self {
        case .sourceNotFound(let sourceId):
            return "Source not found: \(sourceId)"
        case .multiSourceError(let errors):
            return "Multiple sources failed: \(errors.count) errors"
        }
    }
}

// MARK: - Helper Extensions

extension SourceRegistry {
    /// Check if a source is registered
    /// - Parameter sourceId: Source ID to check
    /// - Returns: True if registered, false otherwise
    public func isRegistered(sourceId: String) -> Bool {
        return sources[sourceId] != nil
    }

    /// Get number of registered sources
    /// - Returns: Count of registered sources
    public func sourceCount() -> Int {
        return sources.count
    }
}
