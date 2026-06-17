import Foundation

/// Resolves a person/party name to a real portrait image URL via the Wikipedia
/// REST summary API (images are Wikimedia Commons — largely public-domain US
/// official portraits, or party logos). Results (hits and misses) are cached in
/// memory so the same name is fetched at most once per launch.
///
/// We deliberately do NOT use Kalshi's own images: they aren't in the public API,
/// and they're third-party copyrighted/trademarked assets Kalshi licensed.
actor PortraitService {
    static let shared = PortraitService()

    private var cache: [String: URL?] = [:]
    private let session = URLSession(configuration: .ephemeral)

    /// Returns a portrait URL for `name`, or `nil` if none is found (or the page
    /// is a disambiguation/non-article). Cached after the first lookup.
    func thumbnail(for name: String) async -> URL? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 3, key.contains(" ") || key.count >= 4 else { return nil }
        if let cached = cache[key] { return cached }
        let url = await fetch(key)
        cache[key] = url
        return url
    }

    private func fetch(_ name: String) async -> URL? {
        let title = name.replacingOccurrences(of: " ", with: "_")
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)")
        else { return nil }

        var request = URLRequest(url: url)
        // Wikimedia requires a descriptive User-Agent with contact info.
        request.setValue("Tessera/0.1 (https://github.com/IvanKuria/tessera)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let summary = try JSONDecoder().decode(WikiSummary.self, from: data)
            // Skip disambiguation / no-image pages to avoid wrong matches.
            guard summary.type == "standard", let source = summary.thumbnail?.source else { return nil }
            return URL(string: source)
        } catch {
            return nil
        }
    }

    private struct WikiSummary: Decodable {
        let type: String?
        let thumbnail: Thumb?
        struct Thumb: Decodable { let source: String }
    }
}
