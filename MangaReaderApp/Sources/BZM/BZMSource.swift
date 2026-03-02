import Foundation
import SwiftSoup

/// 包子漫画 (BZM) manga source implementation
/// API Type: JSON API for discovery, HTML scraping for search/info/chapters
/// Reference: MangaReader-master/src/plugins/bzm.ts
public class BZMSource: MangaSourceProtocol {
    // MARK: - Metadata

    public let id = "bzm"
    public let name = "包子漫画"
    public let baseURL = URL(string: "https://cn.baozimhcn.com")!

    public let userAgent: String? = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"

    // MARK: - Initialization

    public init() {}

    // MARK: - Request Preparation

    public func prepareDiscoveryRequest(page: Int, filters: [String: Any]) -> URLRequest {
        // Extract filter parameters with defaults
        let type = (filters["type"] as? String) ?? "all"
        let region = (filters["region"] as? String) ?? "all"
        let status = (filters["status"] as? String) ?? "all"
        let sort = (filters["sort"] as? String) ?? "*"

        var request = URLRequest(url: URL(string: "https://cn.baozimhcn.com/api/bzmhq/amp_comic_list")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let userAgent = userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        request.setValue("https://cn.baozimhcn.com/", forHTTPHeaderField: "Referer")

        // Build request body
        let body: [String: Any] = [
            "type": type,
            "region": region,
            "state": status,
            "filter": sort,
            "page": page,
            "limit": 36,
            "language": "cn",
            "__amp_source_origin": "https://cn.baozimhcn.com/"
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        return request
    }

    public func prepareSearchRequest(keyword: String, page: Int) -> URLRequest {
        // Search returns HTML
        let urlString = "https://cn.baozimhcn.com/search?q=\(keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword)"
        var request = URLRequest(url: URL(string: urlString)!)

        if let userAgent = userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        request.setValue("https://cn.baozimhcn.com/", forHTTPHeaderField: "Referer")

        return request
    }

    public func prepareMangaInfoRequest(mangaId: String) -> URLRequest {
        // Manga info returns HTML with chapters included
        let urlString = "https://cn.baozimhcn.com/comic/\(mangaId)"
        var request = URLRequest(url: URL(string: urlString)!)

        if let userAgent = userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        request.setValue("https://cn.baozimhcn.com/", forHTTPHeaderField: "Referer")

        return request
    }

    public func prepareChapterListRequest(mangaId: String, page: Int?) -> URLRequest? {
        // Chapter list is included in manga info, return nil
        return nil
    }

    public func prepareChapterRequest(mangaId: String, chapterId: String) -> URLRequest {
        // Chapter endpoint returns HTML with images
        // URL format: /comic/chapter/{mangaId}/{chapterId}_{page}.html
        // For first page, use {chapterId}_1.html
        let urlString = "https://cn.dzmanga.com/comic/chapter/\(mangaId)/\(chapterId)_1.html"
        var request = URLRequest(url: URL(string: urlString)!)

        if let userAgent = userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        request.setValue("https://cn.baozimhcn.com/", forHTTPHeaderField: "Referer")

        return request
    }

    // MARK: - Response Handling

    public func handleDiscovery(response: Data) async throws -> [MangaItem] {
        print("📖 [BZM] Parsing discovery response...")

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

        guard let items = json["items"] as? [[String: Any]] else {
            print("   ❌ Missing 'items' key or wrong type")
            if let jsonString = String(data: response, encoding: .utf8) {
                print("   Full response: \(jsonString)")
            }
            throw ParsingError.invalidResponse
        }

        print("   Parsed items array with \(items.count) items")

        let mangaItems = items.compactMap { item in
            parseMangaItem(from: item)
        }

        print("   Successfully parsed \(mangaItems.count) manga items")
        return mangaItems
    }

    public func handleSearch(response: Data) async throws -> [MangaItem] {
        // Parse HTML response
        guard let html = String(data: response, encoding: .utf8) else {
            throw ParsingError.invalidData
        }

        let doc = try SwiftSoup.parse(html)

        // Find manga items in search results
        let items = try doc.select(".classify-items > div")

        var mangaList: [MangaItem] = []

        for item in items {
            // Extract manga ID from href
            let href = try item.select(".comics-card__poster").first()?.attr("href") ?? ""
            guard let mangaId = extractMangaId(from: href) else {
                continue
            }

            // Extract cover
            let cover = try item.select(".comics-card__poster > amp-img").attr("src")

            // Extract author
            let author = try item.select(".comics-card__info .tags").text().trimmingCharacters(in: .whitespaces)

            // Extract title
            let title = try item.select(".comics-card__info .comics-card__title").text().trimmingCharacters(in: .whitespaces)

            // Extract tags
            let tagElements = try item.select(".comics-card__poster .tabs .tab")
            let tags = try tagElements.map { try $0.text().trimmingCharacters(in: .whitespaces) }

            // Clean cover URL (remove query params)
            let cleanCover = cleanCoverURL(cover)

            let manga = MangaItem(
                id: mangaId,
                sourceId: self.id,
                title: title,
                coverURL: cleanCover.flatMap { URL(string: $0) },
                author: author.isEmpty ? nil : author,
                status: nil,
                latest: nil,
                updateTime: nil
            )
            mangaList.append(manga)
        }

        return mangaList
    }

    public func handleMangaInfo(response: Data, mangaId: String) async throws -> MangaDetail {
        guard let html = String(data: response, encoding: .utf8) else {
            throw ParsingError.invalidData
        }

        let doc = try SwiftSoup.parse(html)

        // Extract cover
        let cover = try doc.select(".comics-detail .l-content amp-img").first()?.attr("src") ?? ""

        // Extract title
        let title = try doc.select(".comics-detail .l-content .comics-detail__info .comics-detail__title").first()?.text().trimmingCharacters(in: .whitespaces) ?? ""

        // Extract author
        let author = try doc.select(".comics-detail .l-content .comics-detail__info .comics-detail__author").first()?.text().trimmingCharacters(in: .whitespaces)

        // Extract tags
        let tagElements = try doc.select(".comics-detail .l-content .comics-detail__info .tag-list .tag")
        let allTags = try tagElements.map { try $0.text().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        // Parse status from tags
        var status: MangaStatus = .unknown
        if allTags.contains("连载中") {
            status = .serial
        } else if allTags.contains("已完结") {
            status = .end
        }

        // Remove status tags from tag list
        let tags = allTags.filter { $0 != "连载中" && $0 != "已完结" }

        // Extract latest chapter
        let latest = try doc.select(".comics-detail .l-content .supporting-text > div:not(.tag-list) a").first()?.text() ?? ""

        // Extract update time
        let updateTimeLabel = try doc.select(".comics-detail .l-content .supporting-text > div:not(.tag-list) em").first()?.text() ?? ""
        let updateTime = parseUpdateTime(from: updateTimeLabel)

        // Extract chapters
        var chapters: [Chapter] = []

        // Try multiple selectors for chapter lists
        let chapterDivs = try doc.select("#chapter-items > div, #chapters_other_list > div, .l-content .pure-g > div.comics-chapters")

        for div in chapterDivs {
            let chapterHref = try div.select("a").first()?.attr("href") ?? ""

            // Extract chapter ID from href
            // Pattern: section_slot=123&chapter_slot=456
            guard let chapterId = extractChapterId(from: chapterHref) else {
                continue
            }

            let chapterTitle = try div.select("span").first()?.text() ?? ""

            let chapter = Chapter(
                id: chapterId,
                mangaId: mangaId,
                title: chapterTitle,
                imageURLs: []
            )
            chapters.append(chapter)
        }

        // Reverse to show latest first
        chapters.reverse()

        return MangaDetail(
            id: mangaId,
            sourceId: id,
            title: title,
            coverURL: cleanCoverURL(cover).flatMap { URL(string: $0) },
            author: author,
            artists: [],
            tags: tags,
            status: status,
            latest: latest.isEmpty ? nil : latest,
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
        guard let html = String(data: response, encoding: .utf8) else {
            throw ParsingError.invalidData
        }

        let doc = try SwiftSoup.parse(html)

        // Extract chapter title
        let title = try doc.select(".comic-chapter .header .l-content .title").first()?.text() ?? ""

        // Extract image URLs
        let imageContainers = try doc.select(".comic-contain > div:not(#div_top_ads):not(.mobadsq)")
        var imageURLs: [URL] = []

        for container in imageContainers {
            if let imgSrc = try container.select("amp-img").first()?.attr("src"),
               let url = URL(string: imgSrc) {
                imageURLs.append(url)
            }
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
        guard let comicId = json["comic_id"] as? String,
              let name = json["name"] as? String else {
            return nil
        }

        let topicImg = json["topic_img"] as? String
        let author = json["author"] as? String
        let typeNames = json["type_names"] as? [String]

        var coverURL: URL?
        if let topicImg = topicImg {
            coverURL = URL(string: "https://static-tw.baozimh.com/cover/\(topicImg)")
        }

        return MangaItem(
            id: comicId,
            sourceId: self.id,
            title: name,
            coverURL: coverURL,
            author: author,
            status: nil,
            latest: nil,
            updateTime: nil
        )
    }

    /// Extract manga ID from href
    /// Pattern: /comic/([^_]+)
    private func extractMangaId(from href: String) -> String? {
        let pattern = "/comic/([^_]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: href, range: NSRange(href.startIndex..., in: href)),
              let range = Range(match.range(at: 1), in: href) else {
            return nil
        }
        return String(href[range])
    }

    /// Extract chapter ID from href
    /// Pattern: section_slot=123&chapter_slot=456
    private func extractChapterId(from href: String) -> String? {
        let pattern = "section_slot=([0-9]*)&chapter_slot=([0-9]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: href, range: NSRange(href.startIndex..., in: href)),
              let sectionRange = Range(match.range(at: 1), in: href),
              let chapterRange = Range(match.range(at: 2), in: href) else {
            return nil
        }

        let sectionSlot = String(href[sectionRange])
        let chapterSlot = String(href[chapterRange])

        return "\(sectionSlot)_\(chapterSlot)"
    }

    /// Clean cover URL by removing query parameters
    private func cleanCoverURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString) else {
            return nil
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil

        return components?.url?.absoluteString
    }

    /// Parse update time from label
    /// Supports: "X小时前 更新", "YYYY年MM月DD日", "今天 更新"
    private func parseUpdateTime(from label: String) -> Date? {
        // Pattern: X小时前 更新
        let hourPattern = "([0-9]+)小时前 更新"
        if let hourRegex = try? NSRegularExpression(pattern: hourPattern),
           let match = hourRegex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
           let range = Range(match.range(at: 1), in: label) {
            let hoursAgo = Int(String(label[range])) ?? 0
            return Calendar.current.date(byAdding: .hour, value: -hoursAgo, to: Date())
        }

        // Pattern: YYYY年MM月DD日
        let datePattern = "([0-9]{4}年[0-9]{2}月[0-9]{2}日)"
        if let dateRegex = try? NSRegularExpression(pattern: datePattern),
           let match = dateRegex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
           let range = Range(match.range, in: label) {
            let dateString = String(label[range])

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy年MM月dd日"
            return formatter.date(from: dateString)
        }

        // Pattern: 今天 更新
        if label.contains("今天 更新") {
            return Date()
        }

        return nil
    }
}

// MARK: - Discovery Filter Options

extension BZMSource {
    /// Available filter options for discovery
    public static let discoveryOptions: [String: [DiscoveryOption]] = [
        "type": [
            DiscoveryOption(label: "选择分类", value: "all"),
            DiscoveryOption(label: "全部", value: "all"),
            DiscoveryOption(label: "恋爱", value: "lianai"),
            DiscoveryOption(label: "纯爱", value: "chunai"),
            DiscoveryOption(label: "古风", value: "gufeng"),
            DiscoveryOption(label: "异能", value: "yineng"),
            DiscoveryOption(label: "悬疑", value: "xuanyi"),
            DiscoveryOption(label: "剧情", value: "juqing"),
            DiscoveryOption(label: "科幻", value: "kehuan"),
            DiscoveryOption(label: "奇幻", value: "qihuan"),
            DiscoveryOption(label: "玄幻", value: "xuanhuan"),
            DiscoveryOption(label: "穿越", value: "chuanyue"),
            DiscoveryOption(label: "冒险", value: "mouxian"),
            DiscoveryOption(label: "推理", value: "tuili"),
            DiscoveryOption(label: "武侠", value: "wuxia"),
            DiscoveryOption(label: "格斗", value: "gedou"),
            DiscoveryOption(label: "战争", value: "zhanzheng"),
            DiscoveryOption(label: "热血", value: "rexie"),
            DiscoveryOption(label: "搞笑", value: "gaoxiao"),
            DiscoveryOption(label: "大女主", value: "danuzhu"),
            DiscoveryOption(label: "都市", value: "dushi"),
            DiscoveryOption(label: "总裁", value: "zongcai"),
            DiscoveryOption(label: "后宫", value: "hougong"),
            DiscoveryOption(label: "日常", value: "richang"),
            DiscoveryOption(label: "韩漫", value: "hanman"),
            DiscoveryOption(label: "少年", value: "shaonian"),
            DiscoveryOption(label: "其它", value: "qita")
        ],
        "region": [
            DiscoveryOption(label: "选择地区", value: "all"),
            DiscoveryOption(label: "国漫", value: "cn"),
            DiscoveryOption(label: "日本", value: "jp"),
            DiscoveryOption(label: "韩国", value: "kr"),
            DiscoveryOption(label: "欧美", value: "en")
        ],
        "status": [
            DiscoveryOption(label: "选择状态", value: "all"),
            DiscoveryOption(label: "連載中", value: "serial"),
            DiscoveryOption(label: "完結", value: "pub")
        ],
        "sort": [
            DiscoveryOption(label: "选择排序", value: "*"),
            DiscoveryOption(label: "ABCD", value: "ABCD"),
            DiscoveryOption(label: "EFGH", value: "EFGH"),
            DiscoveryOption(label: "IJKL", value: "IJKL"),
            DiscoveryOption(label: "MNOP", value: "MNOP"),
            DiscoveryOption(label: "QRST", value: "QRST"),
            DiscoveryOption(label: "UVW", value: "UVW"),
            DiscoveryOption(label: "XYZ", value: "XYZ"),
            DiscoveryOption(label: "0-9", value: "0-9")
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
