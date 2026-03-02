import Foundation
import Kingfisher
import UIKit

/// Manages image caching and prefetching using Kingfisher
/// Optimized for manga reading with smart prefetch and memory management
public actor ImageCacheManager {
    public static let shared = ImageCacheManager()

    private let prefetcher: ImagePrefetcher
    private var isConfigured = false

    private init() {
        self.prefetcher = ImagePrefetcher(resources: [])
        Task {
            await configure()
        }
    }

    // MARK: - Configuration

    /// Configure Kingfisher cache settings
    /// Based on research insights from the enhanced plan
    public func configure() {
        guard !isConfigured else { return }

        let cache = ImageCache.default

        // Memory cache configuration (100MB limit)
        cache.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024
        cache.memoryStorage.config.countLimit = 150
        cache.memoryStorage.config.expiration = .seconds(600) // 10 minutes

        // Disk cache configuration (1GB limit)
        cache.diskStorage.config.sizeLimit = 1024 * 1024 * 1024
        cache.diskStorage.config.expiration = .days(7)

        // Default options for image loading
        KingfisherManager.shared.defaultOptions = [
            .backgroundDecode,                    // Decode on background thread
            .scaleFactor(UIScreen.main.scale),   // Auto-scale for device
            .cacheOriginalImage,                  // Cache original image
            .diskCacheExpiration(.days(7)),
            .memoryCacheExpiration(.seconds(600)),
            .retryStrategy(DelayRetryStrategy(maxRetryCount: 3, retryInterval: .seconds(2)))
        ]

        // Memory warning handler
        setupMemoryWarningHandler()

        isConfigured = true
    }

    // MARK: - Prefetching

    /// Prefetch images for current page and surrounding pages
    /// - Parameters:
    ///   - currentPage: Current page index
    ///   - imageURLs: All image URLs in the chapter
    ///   - prefetchRange: Number of pages to prefetch before and after (default: 3)
    ///   - modifyRequest: Optional request modifier (for headers like Referer)
    public func prefetchImages(
        currentPage: Int,
        imageURLs: [URL],
        prefetchRange: Int = 3,
        modifyRequest: ((inout URLRequest) -> Void)? = nil
    ) async {
        let totalPages = imageURLs.count

        // Calculate prefetch range
        let startPage = max(0, currentPage - prefetchRange)
        let endPage = min(totalPages - 1, currentPage + prefetchRange)

        // Collect URLs to prefetch (excluding current page)
        var urlsToPreload: [URL] = []
        for page in startPage...endPage {
            guard page != currentPage, page < imageURLs.count else { continue }
            urlsToPreload.append(imageURLs[page])
        }

        // Configure prefetcher options with request modifier
        var options = KingfisherManager.shared.defaultOptions

        if let modifyRequest = modifyRequest {
            let modifier = AnyModifier { request in
                var modifiedRequest = request
                modifyRequest(&modifiedRequest)
                return modifiedRequest
            }
            options.append(.requestModifier(modifier))
        }

        // Create Source array with URLs
        let sources: [KF.ImageResource] = urlsToPreload.map {
            KF.ImageResource(downloadURL: $0, cacheKey: $0.absoluteString)
        }

        // Start prefetching - create new prefetcher instance
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let newPrefetcher = ImagePrefetcher(
                resources: sources,
                options: options,
                completionHandler: { skipped, failed, completed in
                    continuation.resume()
                }
            )
            newPrefetcher.start()
        }
    }

    /// Stop current prefetching operation
    public func stopPrefetching() {
        prefetcher.stop()
    }

    // MARK: - Cache Management

    /// Get current cache size
    public func getCacheSize() async -> UInt {
        await withCheckedContinuation { continuation in
            ImageCache.default.calculateDiskStorageSize { result in
                switch result {
                case .success(let size):
                    continuation.resume(returning: size)
                case .failure:
                    continuation.resume(returning: 0)
                }
            }
        }
    }

    /// Clear memory cache
    public func clearMemoryCache() {
        ImageCache.default.clearMemoryCache()
    }

    /// Clear disk cache
    public func clearDiskCache() async {
        await withCheckedContinuation { continuation in
            ImageCache.default.clearDiskCache {
                continuation.resume()
            }
        }
    }

    /// Clear all caches
    public func clearAllCaches() async {
        clearMemoryCache()
        await clearDiskCache()
    }

    /// Clear expired cache
    public func clearExpiredCache() async {
        await withCheckedContinuation { continuation in
            ImageCache.default.cleanExpiredDiskCache {
                continuation.resume()
            }
        }
    }

    /// Remove cached image for specific URL
    public func removeCachedImage(for url: URL) {
        ImageCache.default.removeImage(forKey: url.absoluteString)
    }

    // MARK: - Image Download

    /// Download single image with custom headers
    /// - Parameters:
    ///   - url: Image URL
    ///   - headers: Custom headers (e.g., Referer)
    /// - Returns: Downloaded image
    public func downloadImage(url: URL, headers: [String: String]? = nil) async throws -> UIImage {
        let resource = KF.ImageResource(downloadURL: url, cacheKey: url.absoluteString)

        var options = KingfisherManager.shared.defaultOptions

        if let headers = headers {
            let modifier = AnyModifier { request in
                var modifiedRequest = request
                headers.forEach { modifiedRequest.setValue($1, forHTTPHeaderField: $0) }
                return modifiedRequest
            }
            options.append(.requestModifier(modifier))
        }

        return try await withCheckedThrowingContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: resource, options: options) { result in
                switch result {
                case .success(let imageResult):
                    continuation.resume(returning: imageResult.image)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Memory Management

    private func setupMemoryWarningHandler() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleMemoryWarning()
            }
        }
    }

    private func handleMemoryWarning() {
        // Clear memory cache
        clearMemoryCache()

        // Stop prefetching
        stopPrefetching()

        // Reduce memory cache limit temporarily
        ImageCache.default.memoryStorage.config.totalCostLimit = 50 * 1024 * 1024 // 50MB

        // Reset to normal after 60 seconds
        Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            ImageCache.default.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024
        }
    }
}

// MARK: - Helper Extensions

extension KF.ImageResource {
    /// Create resource with custom cache key
    static func manga(url: URL, sourceId: String, mangaId: String) -> KF.ImageResource {
        let cacheKey = "\(sourceId)_\(mangaId)_\(url.lastPathComponent)"
        return KF.ImageResource(downloadURL: url, cacheKey: cacheKey)
    }
}

// MARK: - Downsampling Processor

/// Custom image processor for downsampling large images
public struct MangaImageProcessor: ImageProcessor {
    public let identifier: String
    private let targetSize: CGSize

    public init(targetSize: CGSize) {
        self.targetSize = targetSize
        self.identifier = "com.mangareader.downsample.\(targetSize.width)x\(targetSize.height)"
    }

    public func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
        switch item {
        case .image(let image):
            return image.kf.resize(to: targetSize, for: .aspectFit)
        case .data(let data):
            // Decode image from data with proper scale
            guard let image = KFCrossPlatformImage(data: data, scale: UIScreen.main.scale) else {
                return nil
            }
            return image.kf.resize(to: targetSize, for: .aspectFit)
        }
    }
}

// MARK: - Cache Statistics

public struct CacheStatistics {
    public let memoryCacheSize: UInt
    public let diskCacheSize: UInt
    public let totalCacheSize: UInt
    public let imageCount: Int

    public var formattedMemorySize: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryCacheSize), countStyle: .file)
    }

    public var formattedDiskSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(diskCacheSize), countStyle: .file)
    }

    public var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalCacheSize), countStyle: .file)
    }
}

extension ImageCacheManager {
    /// Get detailed cache statistics
    public func getCacheStatistics() async -> CacheStatistics {
        let diskSize = await getCacheSize()
        // In Kingfisher 7.x, memory cache size is not publicly accessible
        let memorySize: UInt = 0

        return CacheStatistics(
            memoryCacheSize: memorySize,
            diskCacheSize: diskSize,
            totalCacheSize: memorySize + diskSize,
            imageCount: 0  // keys property is internal in Kingfisher 7.x
        )
    }
}
