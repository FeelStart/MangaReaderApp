import Foundation
import Alamofire

/// Network service for manga source requests
/// Wraps Alamofire with retry logic, timeout control, and error handling
public actor NetworkService {
    public static let shared = NetworkService()

    private let session: Session
    private let retryPolicy: RetryPolicy

    private init() {
        // Configure URLSession
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.timeoutIntervalForRequest = 30
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpShouldUsePipelining = true

        // URL cache configuration
        configuration.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,  // 20MB memory
            diskCapacity: 100 * 1024 * 1024,   // 100MB disk
            diskPath: "network_cache"
        )

        // Retry policy: retry up to 3 times with exponential backoff
        self.retryPolicy = RetryPolicy(
            retryLimit: 3,
            exponentialBackoffBase: 2,
            exponentialBackoffScale: 0.5,
            retryableHTTPStatusCodes: Set([408, 429, 500, 502, 503, 504])
        )

        // Configure server trust for manga sources (disable certificate validation)
        let serverTrustManager = ServerTrustManager(evaluators: [
            // DMZJ domains
            "dmzj.com": DisabledTrustEvaluator(),
            "idmzj.com": DisabledTrustEvaluator(),
            "m.idmzj.com": DisabledTrustEvaluator(),
            "www.dmzj.com": DisabledTrustEvaluator(),
            "api.dmzj.com": DisabledTrustEvaluator(),
            "v3api.dmzj.com": DisabledTrustEvaluator(),
            "images.dmzj.com": DisabledTrustEvaluator(),
            // COPY Manga domains (mangacopy.com)
            "mangacopy.com": DisabledTrustEvaluator(),
            "www.mangacopy.com": DisabledTrustEvaluator(),
            "api.mangacopy.com": DisabledTrustEvaluator(),
            "cdn.mangacopy.com": DisabledTrustEvaluator(),
            // COPY Manga alternate domains
            "copymanga.site": DisabledTrustEvaluator(),
            "copymanga.tv": DisabledTrustEvaluator(),
            "copymanga.com": DisabledTrustEvaluator(),
            "www.copymanga.site": DisabledTrustEvaluator(),
            "www.copymanga.tv": DisabledTrustEvaluator(),
            "api.copymanga.site": DisabledTrustEvaluator(),
            "api.copymanga.tv": DisabledTrustEvaluator(),
            // BZM domains (baozimhcn.com - note the 'cn' in domain name)
            "baozimhcn.com": DisabledTrustEvaluator(),
            "cn.baozimhcn.com": DisabledTrustEvaluator(),
            "www.baozimhcn.com": DisabledTrustEvaluator(),
            "api.baozimhcn.com": DisabledTrustEvaluator(),
            // BZM alternate domains
            "baozimh.com": DisabledTrustEvaluator(),
            "cn.baozimh.com": DisabledTrustEvaluator(),
            "www.baozimh.com": DisabledTrustEvaluator(),
            "api.baozimh.com": DisabledTrustEvaluator(),
            // BZM chapter domain
            "dzmanga.com": DisabledTrustEvaluator(),
            "cn.dzmanga.com": DisabledTrustEvaluator(),
            "www.dzmanga.com": DisabledTrustEvaluator(),
            // BZM image/CDN domains
            "static-tw.baozimh.com": DisabledTrustEvaluator(),
            "twmanga.com": DisabledTrustEvaluator(),
            "www.twmanga.com": DisabledTrustEvaluator(),
            // Additional DMZJ image domains
            "images.idmzj.com": DisabledTrustEvaluator()
        ])

        // Create session with interceptor and server trust manager
        self.session = Session(
            configuration: configuration,
            interceptor: Interceptor(adapters: [], retriers: [retryPolicy]),
            serverTrustManager: serverTrustManager
        )
    }

    // MARK: - Public Methods

    /// Perform a network request
    /// - Parameters:
    ///   - request: URLRequest to execute
    ///   - timeout: Optional custom timeout (defaults to 30s)
    /// - Returns: Response data
    /// - Throws: NetworkError if request fails
    public func request(_ urlRequest: URLRequest, timeout: TimeInterval? = nil) async throws -> Data {
        var modifiedRequest = urlRequest

        // Apply custom timeout if specified
        if let timeout = timeout {
            modifiedRequest.timeoutInterval = timeout
        }

        // Log request details
        print("🌐 [NetworkService] Sending request:")
        print("   URL: \(modifiedRequest.url?.absoluteString ?? "nil")")
        print("   Method: \(modifiedRequest.httpMethod ?? "GET")")
        if let headers = modifiedRequest.allHTTPHeaderFields {
            print("   Headers: \(headers)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            session.request(modifiedRequest)
                .validate(statusCode: 200..<300)
                .responseData { response in
                    // Log response details
                    print("📥 [NetworkService] Received response:")
                    print("   URL: \(response.request?.url?.absoluteString ?? "nil")")
                    print("   Status Code: \(response.response?.statusCode ?? -1)")
                    if let data = response.data {
                        print("   Data Size: \(data.count) bytes")
                    } else {
                        print("   Data Size: 0 bytes (nil)")
                    }
                    if let error = response.error {
                        print("   Error: \(error)")
                    }

                    switch response.result {
                    case .success(let data):
                        continuation.resume(returning: data)
                    case .failure(let error):
                        continuation.resume(throwing: self.mapError(error, response: response))
                    }
                }
        }
    }

    /// Perform a request and decode JSON response
    /// - Parameters:
    ///   - request: URLRequest to execute
    ///   - type: Decodable type to decode into
    ///   - decoder: Optional custom JSONDecoder
    /// - Returns: Decoded object
    /// - Throws: NetworkError if request or decoding fails
    public func requestDecodable<T: Decodable>(
        _ urlRequest: URLRequest,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let data = try await request(urlRequest)

        // Log raw response for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📡 Response for \(urlRequest.url?.absoluteString ?? "unknown"):")
            print(jsonString.prefix(500))  // Print first 500 characters
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("❌ Decoding failed for type \(T.self)")
            print("Error: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .dataCorrupted(let context):
                    print("Data corrupted: \(context)")
                case .keyNotFound(let key, let context):
                    print("Key '\(key)' not found: \(context.debugDescription)")
                    print("Coding path: \(context.codingPath)")
                case .typeMismatch(let type, let context):
                    print("Type '\(type)' mismatch: \(context.debugDescription)")
                    print("Coding path: \(context.codingPath)")
                case .valueNotFound(let type, let context):
                    print("Value '\(type)' not found: \(context.debugDescription)")
                    print("Coding path: \(context.codingPath)")
                @unknown default:
                    print("Unknown decoding error")
                }
            }
            throw NetworkError.decodingFailed(error)
        }
    }

    /// Download an image
    /// - Parameters:
    ///   - url: Image URL
    ///   - headers: Optional custom headers (e.g., Referer)
    /// - Returns: Image data
    /// - Throws: NetworkError if download fails
    public func downloadImage(
        url: URL,
        headers: [String: String]? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        return try await self.request(request)
    }

    /// Cancel all ongoing requests
    public func cancelAllRequests() {
        session.cancelAllRequests()
    }

    // MARK: - Error Mapping

    private func mapError(_ error: AFError, response: DataResponse<Data, AFError>) -> NetworkError {
        switch error {
        case .sessionTaskFailed(let underlyingError):
            if let urlError = underlyingError as? URLError {
                switch urlError.code {
                case .timedOut:
                    return .timeout
                case .notConnectedToInternet, .networkConnectionLost:
                    return .noConnection
                default:
                    return .connectionFailed(urlError)
                }
            }
            return .unknown(underlyingError)

        case .responseValidationFailed(let reason):
            if case .unacceptableStatusCode(let code) = reason {
                return .httpError(code)
            }
            return .invalidResponse

        default:
            return .unknown(error)
        }
    }
}

// MARK: - Network Errors

public enum NetworkError: LocalizedError {
    case timeout
    case noConnection
    case connectionFailed(Error)
    case httpError(Int)
    case invalidResponse
    case decodingFailed(Error)
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "请求超时"
        case .noConnection:
            return "无网络连接"
        case .connectionFailed(let error):
            return "连接失败: \(error.localizedDescription)"
        case .httpError(let code):
            return "HTTP 错误: \(code)"
        case .invalidResponse:
            return "无效的响应"
        case .decodingFailed(let error):
            return "数据解析失败: \(error.localizedDescription)"
        case .unknown(let error):
            return "未知错误: \(error.localizedDescription)"
        }
    }

    public var isRecoverable: Bool {
        switch self {
        case .timeout, .noConnection, .connectionFailed:
            return true
        case .httpError(let code):
            return code >= 500 // Server errors are potentially recoverable
        default:
            return false
        }
    }
}

// MARK: - Request Builder Helpers

extension URLRequest {
    /// Add common manga source headers
    public mutating func addMangaSourceHeaders(
        userAgent: String? = nil,
        referer: String? = nil,
        additionalHeaders: [String: String] = [:]
    ) {
        // Default User-Agent if none specified
        let defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
        setValue(userAgent ?? defaultUserAgent, forHTTPHeaderField: "User-Agent")

        // Referer (for anti-hotlinking)
        if let referer = referer {
            setValue(referer, forHTTPHeaderField: "Referer")
        }

        // Additional custom headers
        additionalHeaders.forEach { setValue($1, forHTTPHeaderField: $0) }

        // Accept headers
        setValue("*/*", forHTTPHeaderField: "Accept")
        setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
    }
}

// MARK: - Retry Policy

private class RetryPolicy: RequestRetrier {
    let retryLimit: UInt
    let exponentialBackoffBase: UInt
    let exponentialBackoffScale: Double
    let retryableHTTPStatusCodes: Set<Int>

    init(
        retryLimit: UInt,
        exponentialBackoffBase: UInt,
        exponentialBackoffScale: Double,
        retryableHTTPStatusCodes: Set<Int>
    ) {
        self.retryLimit = retryLimit
        self.exponentialBackoffBase = exponentialBackoffBase
        self.exponentialBackoffScale = exponentialBackoffScale
        self.retryableHTTPStatusCodes = retryableHTTPStatusCodes
    }

    func retry(
        _ request: Alamofire.Request,
        for session: Session,
        dueTo error: Error,
        completion: @escaping (RetryResult) -> Void
    ) {
        guard request.retryCount < retryLimit else {
            completion(.doNotRetry)
            return
        }

        // Check if error is retryable
        if let statusCode = request.response?.statusCode,
           retryableHTTPStatusCodes.contains(statusCode) {
            let delay = calculateDelay(for: UInt(request.retryCount))
            completion(.retryWithDelay(delay))
            return
        }

        // Check for network errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                let delay = calculateDelay(for: UInt(request.retryCount))
                completion(.retryWithDelay(delay))
                return
            default:
                break
            }
        }

        completion(.doNotRetry)
    }

    private func calculateDelay(for retryCount: UInt) -> TimeInterval {
        let delay = pow(Double(exponentialBackoffBase), Double(retryCount)) * exponentialBackoffScale
        return min(delay, 30.0) // Max 30 seconds
    }
}
