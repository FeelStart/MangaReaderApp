import Foundation
import SwiftSoup

/// 拷贝漫画 (COPY) manga source implementation
/// API Type: JSON API with HTML scraping and AES encryption
/// Reference: MangaReader-master/src/plugins/copy.ts
public class COPYSource: MangaSourceProtocol {
    // MARK: - Metadata

    public let id = "copy"
    public let name = "拷贝漫画"
    public let baseURL = URL(string: "https://www.mangacopy.com")!

    public let userAgent: String? = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// Encryption key for manga info (extracted from HTML)
    private var mangaInfoKey: String?

    /// Encryption key for chapters (extracted from HTML)
    private var chapterKey: String?

    // MARK: - Initialization

    public init() {}

    // MARK: - Request Preparation

    public func prepareDiscoveryRequest(page: Int, filters: [String: Any]) -> URLRequest {
        // Extract filter parameters with defaults
        let theme = (filters["theme"] as? String) ?? "-1"
        let top = (filters["top"] as? String) ?? "-1"
        let status = (filters["status"] as? String) ?? "-1"
        let ordering = (filters["ordering"] as? String) ?? "-popular"
        let offset = (page - 1) * 50
        let limit = 50

        // Build URL with query parameters
        var components = URLComponents(string: "https://api.mangacopy.com/api/v3/comics")!
        components.queryItems = [
            URLQueryItem(name: "theme", value: theme),
            URLQueryItem(name: "top", value: top),
            URLQueryItem(name: "status", value: status),
            URLQueryItem(name: "ordering", value: ordering),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"  // Changed from POST to GET

        if let userAgent = userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        return request
    }

    public func prepareSearchRequest(keyword: String, page: Int) -> URLRequest {
        let offset = (page - 1) * 50
        let limit = 50

        // Build URL with query parameters
        var components = URLComponents(string: "https://api.mangacopy.com/api/v3/search/comic")!
        components.queryItems = [
            URLQueryItem(name: "q", value: keyword),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "q_type", value: "")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"  // Changed from POST to GET

        if let userAgent = userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        return request
    }

    public func prepareMangaInfoRequest(mangaId: String) -> URLRequest {
        // Manga info returns HTML with embedded encryption key
        let urlString = "https://www.mangacopy.com/comic/\(mangaId)"
        var request = URLRequest(url: URL(string: urlString)!)

        if let userAgent = userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        return request
    }

    public func prepareChapterListRequest(mangaId: String, page: Int?) -> URLRequest? {
        // Chapter list is separate from manga info
        let urlString = "https://www.mangacopy.com/comicdetail/\(mangaId)/chapters"
        var request = URLRequest(url: URL(string: urlString)!)

        if let userAgent = userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        return request
    }

    public func prepareChapterRequest(mangaId: String, chapterId: String) -> URLRequest {
        // Chapter endpoint returns HTML with encrypted image URLs
        let urlString = "https://www.mangacopy.com/comic/\(mangaId)/chapter/\(chapterId)"
        var request = URLRequest(url: URL(string: urlString)!)

        if let userAgent = userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        return request
    }

    // MARK: - Response Handling

    public func handleDiscovery(response: Data) async throws -> [MangaItem] {
        print("📖 [COPY] Parsing discovery response...")

        // Log raw response
        if let jsonString = String(data: response, encoding: .utf8) {
            print("   Raw response (first 1000 chars): \(String(jsonString.prefix(1000)))")
        }

        // Parse JSON response
        guard let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            print("   ❌ Failed to parse as JSON object")
            throw ParsingError.invalidResponse
        }

        print("   JSON keys: \(json.keys)")

        guard let results = json["results"] as? [String: Any] else {
            print("   ❌ Missing 'results' key")
            throw ParsingError.invalidResponse
        }

        print("   Results keys: \(results.keys)")

        guard let list = results["list"] as? [[String: Any]] else {
            print("   ❌ Missing 'list' key in results")
            throw ParsingError.invalidResponse
        }

        print("   Parsed list with \(list.count) items")

        let items = list.compactMap { item in
            parseMangaItem(from: item)
        }

        print("   Successfully parsed \(items.count) manga items")
        return items
    }

    public func handleSearch(response: Data) async throws -> [MangaItem] {
        // Parse JSON response
        guard let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let list = results["list"] as? [[String: Any]] else {
            throw ParsingError.invalidResponse
        }

        return list.compactMap { item in
            parseMangaItem(from: item)
        }
    }

    public func handleMangaInfo(response: Data, mangaId: String) async throws -> MangaDetail {
        guard let html = String(data: response, encoding: .utf8) else {
            throw ParsingError.invalidData
        }

        let doc = try SwiftSoup.parse(html)

        // Extract encryption key for chapter list
        // Pattern: var ccx = '...';
        let scripts = try doc.select("script:not([src])")
        for script in scripts {
            let scriptContent = try script.html()
            if let range = scriptContent.range(of: "var ccx = '") {
                let startIndex = range.upperBound
                if let endRange = scriptContent[startIndex...].range(of: "';") {
                    mangaInfoKey = String(scriptContent[startIndex..<endRange.lowerBound])
                }
                break
            }
        }

        // Extract manga metadata
        let cover = try doc.select("div.exemptComic-img img").first()
        let title = try cover?.attr("alt") ?? ""
        let coverURL = try cover?.attr("data-src")

        // Extract author
        let authorLink = try doc.select("div.exemptComic-right a.exemptComic-author").first()
        let author = try authorLink?.text()

        // Extract tags
        let tagElements = try doc.select("div.exemptComic-right span.exemptComic-tag")
        let tags = try tagElements.map { try $0.text() }

        // Extract status
        let statusElement = try doc.select("div.exemptComic-right span.exemptComic-status").first()
        let statusText = try statusElement?.text()
        var status: MangaStatus = .unknown
        if let statusText = statusText {
            if statusText.contains("连载") {
                status = .serial
            } else if statusText.contains("完结") {
                status = .end
            }
        }

        // Extract description
        let descElement = try doc.select("div.exemptComicDetail p.exemptComicDetail-txt").first()
        let description = try descElement?.text()

        // Extract latest chapter
        let latestElement = try doc.select("div.exemptComic-right span.exemptComic-update").first()
        let latest = try latestElement?.text()

        // Note: Chapters need separate request to chapter list endpoint
        return MangaDetail(
            id: mangaId,
            sourceId: id,
            title: title,
            coverURL: coverURL.flatMap { URL(string: $0) },
            author: author,
            artists: [],
            tags: tags,
            status: status,
            latest: latest,
            updateTime: nil,
            description: description,
            chapters: []
        )
    }

    public func handleChapterList(response: Data, mangaId: String) async throws -> [Chapter] {
        guard let html = String(data: response, encoding: .utf8) else {
            throw ParsingError.invalidData
        }

        let doc = try SwiftSoup.parse(html)

        // Find encrypted chapter data
        // Pattern: <div class="imageData" contentkey="..."></div>
        guard let imageDataDiv = try doc.select("div.imageData").first(),
              let contentKey = try? imageDataDiv.attr("contentkey"),
              !contentKey.isEmpty else {
            throw ParsingError.elementNotFound("contentkey")
        }

        // Decrypt chapter list using stored key
        guard let key = mangaInfoKey else {
            throw ParsingError.invalidResponse
        }

        let decryptedJSON = try AESDecryptor.decrypt(contentKey: contentKey, key: key)

        // Parse decrypted JSON
        guard let jsonData = decryptedJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let groups = json["groups"] as? [[String: Any]] else {
            throw ParsingError.invalidData
        }

        var chapters: [Chapter] = []

        for group in groups {
            if let chapterList = group["chapters"] as? [[String: Any]] {
                for chapterData in chapterList {
                    guard let chapterIdInt = chapterData["id"] as? Int,
                          let chapterName = chapterData["name"] as? String else {
                        continue
                    }

                    let chapter = Chapter(
                        id: String(chapterIdInt),
                        mangaId: mangaId,
                        title: chapterName,
                        imageURLs: []
                    )
                    chapters.append(chapter)
                }
            }
        }

        return chapters.reversed() // Reverse to show latest first
    }

    public func handleChapter(response: Data, mangaId: String, chapterId: String) async throws -> Chapter {
        guard let html = String(data: response, encoding: .utf8) else {
            throw ParsingError.invalidData
        }

        let doc = try SwiftSoup.parse(html)

        // Extract encryption key for chapter images
        // Pattern: var ccy = '...';
        let scripts = try doc.select("script:not([src])")
        for script in scripts {
            let scriptContent = try script.html()
            if let range = scriptContent.range(of: "var ccy = '") {
                let startIndex = range.upperBound
                if let endRange = scriptContent[startIndex...].range(of: "';") {
                    chapterKey = String(scriptContent[startIndex..<endRange.lowerBound])
                }
                break
            }
        }

        // Find encrypted image data
        guard let imageDataDiv = try doc.select("div.imageData").first(),
              let contentKey = try? imageDataDiv.attr("contentkey"),
              !contentKey.isEmpty else {
            throw ParsingError.elementNotFound("contentkey")
        }

        // Decrypt image URLs using chapter key
        guard let key = chapterKey else {
            throw ParsingError.invalidResponse
        }

        let decryptedJSON = try AESDecryptor.decrypt(contentKey: contentKey, key: key)

        // Parse decrypted JSON
        guard let jsonData = decryptedJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let chapterInfo = json["chapter"] as? [String: Any],
              let title = chapterInfo["name"] as? String,
              let contents = chapterInfo["contents"] as? [[String: Any]] else {
            throw ParsingError.invalidData
        }

        // Extract image URLs
        let imageURLs = contents.compactMap { content -> URL? in
            guard let urlString = content["url"] as? String else { return nil }
            return URL(string: urlString)
        }

        return Chapter(
            id: chapterId,
            mangaId: mangaId,
            title: title,
            imageURLs: imageURLs
        )
    }

    // MARK: - Helper Methods

    /// Parse manga item from JSON dictionary
    private func parseMangaItem(from json: [String: Any]) -> MangaItem? {
        guard let pathword = json["path_word"] as? String,
              let name = json["name"] as? String else {
            return nil
        }

        let cover = json["cover"] as? String
        let author = (json["author"] as? [[String: Any]])?.first?["name"] as? String
        let popular = json["popular"] as? Int

        // Parse status
        var status: MangaStatus?
        if let statusArray = json["status"] as? [[String: Any]],
           let statusItem = statusArray.first,
           let statusValue = statusItem["value"] as? Int {
            switch statusValue {
            case 0:
                status = .serial
            case 1:
                status = .end
            default:
                status = .unknown
            }
        }

        return MangaItem(
            id: pathword,
            sourceId: self.id,
            title: name,
            coverURL: cover.flatMap { URL(string: $0) },
            author: author,
            status: status,
            latest: nil,
            updateTime: nil
        )
    }
}

// MARK: - Discovery Filter Options

extension COPYSource {
    /// Available filter options for discovery
    public static let discoveryOptions: [String: [DiscoveryOption]] = [
        "theme": [
            DiscoveryOption(label: "全部", value: "-1"),
            DiscoveryOption(label: "恋爱", value: "0"),
            DiscoveryOption(label: "纯爱", value: "1"),
            DiscoveryOption(label: "古风", value: "2"),
            DiscoveryOption(label: "异能", value: "3"),
            DiscoveryOption(label: "悬疑", value: "4"),
            DiscoveryOption(label: "剧情", value: "5"),
            DiscoveryOption(label: "科幻", value: "6"),
            DiscoveryOption(label: "奇幻", value: "7"),
            DiscoveryOption(label: "玄幻", value: "8"),
            DiscoveryOption(label: "穿越", value: "9"),
            DiscoveryOption(label: "冒险", value: "10"),
            DiscoveryOption(label: "推理", value: "11"),
            DiscoveryOption(label: "武侠", value: "12"),
            DiscoveryOption(label: "格斗", value: "13"),
            DiscoveryOption(label: "战争", value: "14"),
            DiscoveryOption(label: "热血", value: "15"),
            DiscoveryOption(label: "搞笑", value: "16"),
            DiscoveryOption(label: "大女主", value: "17"),
            DiscoveryOption(label: "都市", value: "18"),
            DiscoveryOption(label: "总裁", value: "19"),
            DiscoveryOption(label: "后宫", value: "20"),
            DiscoveryOption(label: "日常", value: "21"),
            DiscoveryOption(label: "韩漫", value: "22"),
            DiscoveryOption(label: "少年", value: "23"),
            DiscoveryOption(label: "其它", value: "24")
        ],
        "top": [
            DiscoveryOption(label: "全部", value: "-1"),
            DiscoveryOption(label: "月榜", value: "0"),
            DiscoveryOption(label: "周榜", value: "1"),
            DiscoveryOption(label: "日榜", value: "2")
        ],
        "status": [
            DiscoveryOption(label: "全部", value: "-1"),
            DiscoveryOption(label: "连载", value: "0"),
            DiscoveryOption(label: "完结", value: "1")
        ],
        "ordering": [
            DiscoveryOption(label: "人气推荐", value: "-popular"),
            DiscoveryOption(label: "更新时间", value: "-datetime_updated")
        ]
    ]

    public struct DiscoveryOption {
        public let label: String
        public let value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }
}
