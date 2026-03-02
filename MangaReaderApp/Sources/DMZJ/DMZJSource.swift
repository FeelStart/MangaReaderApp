import Foundation
import SwiftSoup

/// 动漫之家 (DMZJ) manga source implementation
/// API Type: JSON API with some HTML scraping
/// Reference: MangaReader-master/src/plugins/dmzj.ts
public class DMZJSource: MangaSourceProtocol {
    // MARK: - Metadata

    public let id = "dmzj"
    public let name = "动漫之家"
    public let baseURL = URL(string: "https://m.idmzj.com")!

    public let userAgent: String? = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// User ID obtained from login cookie (optional)
    /// Enables access to restricted manga
    private var uid: String?

    // MARK: - Initialization

    public init(uid: String? = nil) {
        self.uid = uid
    }

    // MARK: - Request Preparation

    public func prepareDiscoveryRequest(page: Int, filters: [String: Any]) -> URLRequest {
        // Extract filter parameters with defaults
        let type = (filters["type"] as? String) ?? "0"
        let region = (filters["region"] as? String) ?? "0"
        let status = (filters["status"] as? String) ?? "0"
        let sort = (filters["sort"] as? String) ?? "1"

        // URL format: /classify/{type}-0-{status}-{region}-{sort}-{page-1}.json
        // Page is 0-indexed in API
        let urlString = "https://m.idmzj.com/classify/\(type)-0-\(status)-\(region)-\(sort)-\(page - 1).json"
        var request = URLRequest(url: URL(string: urlString)!)

        if let userAgent = userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        return request
    }

    public func prepareSearchRequest(keyword: String, page: Int) -> URLRequest {
        // Search returns HTML with embedded JSON in script tag
        let urlString = "https://m.idmzj.com/search/\(keyword.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? keyword).html"
        var request = URLRequest(url: URL(string: urlString)!)

        if let userAgent = userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        return request
    }

    public func prepareMangaInfoRequest(mangaId: String) -> URLRequest {
        // Manga info returns HTML with embedded JSON in script tag
        let urlString = "https://m.idmzj.com/info/\(mangaId).html"
        var request = URLRequest(url: URL(string: urlString)!)

        if let userAgent = userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        return request
    }

    public func prepareChapterRequest(mangaId: String, chapterId: String) -> URLRequest {
        // Chapter endpoint is a POST request to API
        var request = URLRequest(url: URL(string: "https://www.idmzj.com/api/v1/comic1/chapter/detail")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let userAgent = userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        // Build request body
        let timestamp = Int(Date().timeIntervalSince1970)
        let body: [String: Any] = [
            "channel": "pc",
            "app_name": "dmzj",
            "version": "1.0.0",
            "timestamp": timestamp,
            "uid": uid ?? "",
            "comic_id": mangaId,
            "chapter_id": chapterId
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        return request
    }

    // MARK: - Response Handling

    public func handleDiscovery(response: Data) async throws -> [MangaItem] {
        print("📖 [DMZJ] Parsing discovery response...")

        // Log raw response
        if let jsonString = String(data: response, encoding: .utf8) {
            print("   Raw response (first 1000 chars): \(String(jsonString.prefix(1000)))")
        }

        // Parse JSON response
        guard let json = try? JSONSerialization.jsonObject(with: response) as? [[String: Any]] else {
            print("   ❌ Failed to parse as JSON array")
            if let jsonString = String(data: response, encoding: .utf8) {
                print("   Response preview: \(String(jsonString.prefix(500)))")
            }
            throw ParsingError.invalidResponse
        }

        print("   Parsed JSON array with \(json.count) items")

        let items = json.compactMap { item in
            parseMangaItem(from: item)
        }

        print("   Successfully parsed \(items.count) manga items")
        return items
    }

    public func handleSearch(response: Data) async throws -> [MangaItem] {
        // Parse HTML to extract embedded JSON
        guard let html = String(data: response, encoding: .utf8) else {
            throw ParsingError.invalidData
        }

        let doc = try SwiftSoup.parse(html)

        // Find script tag containing search results
        // Pattern: var serchArry=...
        let scripts = try doc.select("script:not([src]):not([type])")
        var jsonString: String?

        for script in scripts {
            let scriptContent = try script.html()
            if let range = scriptContent.range(of: "var serchArry=") {
                let startIndex = range.upperBound
                // Find the end of the JSON array (look for semicolon or end of line)
                if let endRange = scriptContent[startIndex...].range(of: ";") {
                    jsonString = String(scriptContent[startIndex..<endRange.lowerBound])
                }
                break
            }
        }

        guard let jsonString = jsonString else {
            throw ParsingError.elementNotFound("serchArry script")
        }

        // Remove newlines and spaces
        let cleanedJSON = jsonString.replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard let jsonData = cleanedJSON.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            throw ParsingError.invalidData
        }

        return items.compactMap { parseMangaItem(from: $0) }
    }

    public func handleMangaInfo(response: Data, mangaId: String) async throws -> MangaDetail {
        guard let html = String(data: response, encoding: .utf8) else {
            throw ParsingError.invalidData
        }

        // Check for copyright restriction
        if html.contains("因版权、国家法规等原因，此漫画暂不提供观看，敬请谅解。") {
            throw ParsingError.invalidResponse
        }

        let doc = try SwiftSoup.parse(html)

        // Extract manga info from script tag
        // Pattern: initIntroData(...);
        let scripts = try doc.select("script:not([src])")
        var chapterData: [[String: Any]]?
        var statusLabel: String?

        for script in scripts {
            let scriptContent = try script.html()
            if let range = scriptContent.range(of: "initIntroData(") {
                let startIndex = range.upperBound
                if let endRange = scriptContent[startIndex...].range(of: ");") {
                    let jsonString = String(scriptContent[startIndex..<endRange.lowerBound])
                    if let jsonData = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]],
                       let firstItem = json.first {
                        statusLabel = firstItem["title"] as? String
                        chapterData = firstItem["data"] as? [[String: Any]]
                    }
                }
                break
            }
        }

        guard let chapterData = chapterData else {
            throw ParsingError.elementNotFound("initIntroData")
        }

        // Parse chapters
        let chapters = chapterData.compactMap { item -> Chapter? in
            guard let id = item["id"] as? Int,
                  let comicId = item["comic_id"] as? Int,
                  let chapterName = item["chapter_name"] as? String else {
                return nil
            }

            return Chapter(
                id: String(id),
                mangaId: String(comicId),
                title: chapterName,
                imageURLs: []
            )
        }

        // Extract manga metadata from HTML
        let cover = try doc.select("div.Introduct_Sub div#Cover img").first()
        let title = try cover?.attr("title") ?? ""
        let coverURL = try cover?.attr("src")

        let infoItems = try doc.select("div.Introduct_Sub div.sub_r p.txtItme")
        var author: String?
        var tags: [String] = []
        var updateTime: Date?

        if infoItems.count >= 4 {
            // Author (first item)
            let authorElements = try infoItems[0].select("a")
            author = try authorElements.map { try $0.text() }.joined(separator: ", ")

            // Tags (second item)
            let tagElements = try infoItems[1].select("a")
            tags = try tagElements.map { try $0.text() }

            // Update time (fourth item)
            if let timeSpan = try infoItems[3].select("span").first() {
                let timeText = try timeSpan.text()
                updateTime = parseDate(from: timeText)
            }
        }

        // Parse status
        var status: MangaStatus = .unknown
        if let statusLabel = statusLabel {
            if statusLabel == "连载" {
                status = .serial
            } else if statusLabel == "完结" {
                status = .end
            }
        }

        return MangaDetail(
            id: mangaId,
            sourceId: id,
            title: title,
            coverURL: coverURL.flatMap { URL(string: "https://images.idmzj.com/\($0)") },
            author: author,
            artists: [],
            tags: tags,
            status: status,
            latest: chapters.first?.title,
            updateTime: updateTime,
            description: nil,
            chapters: chapters
        )
    }

    public func handleChapterList(response: Data, mangaId: String) async throws -> [Chapter] {
        // Chapter list is included in manga info, not separate
        throw ParsingError.invalidResponse
    }

    public func handleChapter(response: Data, mangaId: String, chapterId: String) async throws -> Chapter {
        // Parse JSON response
        guard let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            throw ParsingError.invalidResponse
        }

        // Check error code
        guard let errno = json["errno"] as? Int, errno == 0 else {
            let errmsg = json["errmsg"] as? String ?? "Unknown error"
            if errmsg == "漫画不存在" && uid == nil {
                throw ParsingError.invalidResponse
            }
            throw ParsingError.invalidResponse
        }

        guard let data = json["data"] as? [String: Any],
              let chapterInfo = data["chapterInfo"] as? [String: Any] else {
            throw ParsingError.elementNotFound("chapterInfo")
        }

        let title = chapterInfo["title"] as? String ?? ""
        let pageURLs = chapterInfo["page_url"] as? [String] ?? []

        // Convert page URLs to full URLs
        let imageURLs = pageURLs.compactMap { URL(string: $0) }

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
        guard let idValue = json["id"],
              let name = json["name"] as? String else {
            return nil
        }

        // Handle id as either Int or String
        let id: String
        if let intId = idValue as? Int {
            id = String(intId)
        } else if let stringId = idValue as? String {
            id = stringId
        } else {
            return nil
        }

        let cover = json["cover"] as? String
        let authors = json["authors"] as? String
        let statusString = json["status"] as? String
        let latestChapter = json["last_update_chapter_name"] as? String
        let updateTimestamp = json["last_updatetime"] as? Int

        var status: MangaStatus?
        if let statusString = statusString {
            if statusString == "连载中" {
                status = .serial
            } else if statusString == "已完结" {
                status = .end
            }
        }

        var updateTime: Date?
        if let timestamp = updateTimestamp {
            updateTime = Date(timeIntervalSince1970: TimeInterval(timestamp))
        }

        return MangaItem(
            id: id,
            sourceId: self.id,
            title: name,
            coverURL: cover.flatMap { URL(string: "https://images.idmzj.com/\($0)") },
            author: authors,
            status: status,
            latest: latestChapter,
            updateTime: updateTime
        )
    }

    /// Parse date string to Date
    /// Supports format: YYYY-MM-DD
    private func parseDate(from text: String) -> Date? {
        let pattern = "[0-9]{4}-[0-9]{2}-[0-9]{2}"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }

        let dateString = String(text[Range(match.range, in: text)!])

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
}

// MARK: - Discovery Filter Options

extension DMZJSource {
    /// Available filter options for discovery
    public static let discoveryOptions: [String: [DiscoveryOption]] = [
        "type": [
            DiscoveryOption(label: "选择分类", value: "0"),
            DiscoveryOption(label: "冒险", value: "1"),
            DiscoveryOption(label: "欢乐向", value: "2"),
            DiscoveryOption(label: "格斗", value: "3"),
            DiscoveryOption(label: "科幻", value: "4"),
            DiscoveryOption(label: "爱情", value: "5"),
            DiscoveryOption(label: "竞技", value: "6"),
            DiscoveryOption(label: "魔法", value: "7"),
            DiscoveryOption(label: "校园", value: "8"),
            DiscoveryOption(label: "悬疑", value: "9"),
            DiscoveryOption(label: "恐怖", value: "10"),
            DiscoveryOption(label: "生活亲情", value: "11"),
            DiscoveryOption(label: "百合", value: "12"),
            DiscoveryOption(label: "伪娘", value: "13"),
            DiscoveryOption(label: "耽美", value: "14"),
            DiscoveryOption(label: "后宫", value: "15"),
            DiscoveryOption(label: "萌系", value: "16"),
            DiscoveryOption(label: "治愈", value: "17"),
            DiscoveryOption(label: "武侠", value: "18"),
            DiscoveryOption(label: "职场", value: "19"),
            DiscoveryOption(label: "奇幻", value: "20"),
            DiscoveryOption(label: "节操", value: "21"),
            DiscoveryOption(label: "轻小说", value: "22"),
            DiscoveryOption(label: "搞笑", value: "23")
        ],
        "region": [
            DiscoveryOption(label: "选择地区", value: "0"),
            DiscoveryOption(label: "日本", value: "1"),
            DiscoveryOption(label: "内地", value: "2"),
            DiscoveryOption(label: "欧美", value: "3"),
            DiscoveryOption(label: "港台", value: "4"),
            DiscoveryOption(label: "韩国", value: "5"),
            DiscoveryOption(label: "其他", value: "6")
        ],
        "status": [
            DiscoveryOption(label: "选择状态", value: "0"),
            DiscoveryOption(label: "连载中", value: "1"),
            DiscoveryOption(label: "已完结", value: "2")
        ],
        "sort": [
            DiscoveryOption(label: "选择排序", value: "1"),
            DiscoveryOption(label: "浏览次数", value: "0"),
            DiscoveryOption(label: "更新时间", value: "1")
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
