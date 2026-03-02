import Foundation

/// Protocol that all manga sources must conform to
/// Based on MangaReader-master/src/plugins/base.ts:32-50
public protocol MangaSourceProtocol {
    // MARK: - Metadata

    /// Unique identifier for this source
    var id: String { get }

    /// Display name of the source
    var name: String { get }

    /// Base URL of the manga source
    var baseURL: URL { get }

    /// Optional custom User-Agent for requests
    var userAgent: String? { get }

    /// Default headers to include in all requests
    var defaultHeaders: [String: String] { get }

    // MARK: - Request Preparation

    /// Prepare discovery/browse request (homepage, categories, etc.)
    /// - Parameters:
    ///   - page: Page number (1-indexed)
    ///   - filters: Dictionary of filter parameters (type, status, region, sort, etc.)
    /// - Returns: Configured URLRequest
    func prepareDiscoveryRequest(page: Int, filters: [String: Any]) -> URLRequest

    /// Prepare search request
    /// - Parameters:
    ///   - keyword: Search query
    ///   - page: Page number (1-indexed)
    /// - Returns: Configured URLRequest
    func prepareSearchRequest(keyword: String, page: Int) -> URLRequest

    /// Prepare manga info request (details page)
    /// - Parameter mangaId: Unique manga identifier
    /// - Returns: Configured URLRequest
    func prepareMangaInfoRequest(mangaId: String) -> URLRequest

    /// Prepare chapter list request
    /// - Parameters:
    ///   - mangaId: Unique manga identifier
    ///   - page: Page number (1-indexed), nil if all chapters in one page
    /// - Returns: Configured URLRequest, or nil if chapter list is included in manga info
    func prepareChapterListRequest(mangaId: String, page: Int?) -> URLRequest?

    /// Prepare chapter request (individual chapter page images)
    /// - Parameters:
    ///   - mangaId: Unique manga identifier
    ///   - chapterId: Unique chapter identifier
    /// - Returns: Configured URLRequest
    func prepareChapterRequest(mangaId: String, chapterId: String) -> URLRequest

    // MARK: - Response Handling

    /// Parse discovery response
    /// - Parameter response: Raw response data
    /// - Returns: Array of manga items
    /// - Throws: ParsingError if parsing fails
    func handleDiscovery(response: Data) async throws -> [MangaItem]

    /// Parse search response
    /// - Parameter response: Raw response data
    /// - Returns: Array of manga items
    /// - Throws: ParsingError if parsing fails
    func handleSearch(response: Data) async throws -> [MangaItem]

    /// Parse manga info response
    /// - Parameters:
    ///   - response: Raw response data
    ///   - mangaId: Manga identifier (for reference)
    /// - Returns: Detailed manga information
    /// - Throws: ParsingError if parsing fails
    func handleMangaInfo(response: Data, mangaId: String) async throws -> MangaDetail

    /// Parse chapter list response
    /// - Parameters:
    ///   - response: Raw response data
    ///   - mangaId: Manga identifier (for reference)
    /// - Returns: Array of chapters
    /// - Throws: ParsingError if parsing fails
    func handleChapterList(response: Data, mangaId: String) async throws -> [Chapter]

    /// Parse chapter response (extract image URLs)
    /// - Parameters:
    ///   - response: Raw response data
    ///   - mangaId: Manga identifier (for reference)
    ///   - chapterId: Chapter identifier (for reference)
    /// - Returns: Chapter with image URLs
    /// - Throws: ParsingError if parsing fails
    func handleChapter(response: Data, mangaId: String, chapterId: String) async throws -> Chapter
}

// MARK: - Default Implementations

public extension MangaSourceProtocol {
    /// Default headers include User-Agent if specified
    var defaultHeaders: [String: String] {
        if let userAgent = userAgent {
            return ["User-Agent": userAgent]
        }
        return [:]
    }

    /// Default chapter list request returns nil (assumes chapters are in manga info)
    func prepareChapterListRequest(mangaId: String, page: Int?) -> URLRequest? {
        return nil
    }
}

// MARK: - Supporting Types

/// Simplified manga item for lists
public struct MangaItem: Identifiable, Codable, Hashable {
    public let id: String
    public let sourceId: String
    public let title: String
    public let coverURL: URL?
    public let author: String?
    public let status: MangaStatus?
    public let latest: String?
    public let updateTime: Date?

    public init(id: String, sourceId: String, title: String, coverURL: URL? = nil,
                author: String? = nil, status: MangaStatus? = nil,
                latest: String? = nil, updateTime: Date? = nil) {
        self.id = id
        self.sourceId = sourceId
        self.title = title
        self.coverURL = coverURL
        self.author = author
        self.status = status
        self.latest = latest
        self.updateTime = updateTime
    }
}

/// Detailed manga information
public struct MangaDetail: Codable {
    public let id: String
    public let sourceId: String
    public let title: String
    public let coverURL: URL?
    public let author: String?
    public let artists: [String]
    public let tags: [String]
    public let status: MangaStatus
    public let latest: String?
    public let updateTime: Date?
    public let description: String?
    public let chapters: [Chapter]?

    public init(id: String, sourceId: String, title: String, coverURL: URL? = nil,
                author: String? = nil, artists: [String] = [], tags: [String] = [],
                status: MangaStatus, latest: String? = nil, updateTime: Date? = nil,
                description: String? = nil, chapters: [Chapter]? = nil) {
        self.id = id
        self.sourceId = sourceId
        self.title = title
        self.coverURL = coverURL
        self.author = author
        self.artists = artists
        self.tags = tags
        self.status = status
        self.latest = latest
        self.updateTime = updateTime
        self.description = description
        self.chapters = chapters
    }
}

/// Chapter information
public struct Chapter: Identifiable, Codable, Hashable {
    public let id: String
    public let mangaId: String
    public let title: String
    public var imageURLs: [URL]
    public let updateTime: Date?

    public init(id: String, mangaId: String, title: String,
                imageURLs: [URL] = [], updateTime: Date? = nil) {
        self.id = id
        self.mangaId = mangaId
        self.title = title
        self.imageURLs = imageURLs
        self.updateTime = updateTime
    }
}

/// Manga status enum
public enum MangaStatus: String, Codable {
    case serial = "连载中"
    case end = "已完结"
    case unknown = "未知"
}

/// Parsing errors
public enum ParsingError: LocalizedError {
    case invalidResponse
    case elementNotFound(String)
    case invalidData
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response format"
        case .elementNotFound(let selector):
            return "Required element not found: \(selector)"
        case .invalidData:
            return "Invalid or corrupted data"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
