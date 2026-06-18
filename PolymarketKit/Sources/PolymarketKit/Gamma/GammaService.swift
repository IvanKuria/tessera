import Foundation

// MARK: - Models

/// A Polymarket market as returned by the Gamma `/markets` endpoint.
///
/// The Gamma API has two notable quirks that this model normalizes:
///
/// 1. **JSON-encoded string arrays.** `outcomes`, `outcomePrices` and
///    `clobTokenIds` arrive as JSON *strings* containing a JSON array, e.g.
///    `"outcomePrices": "[\"0.52\",\"0.48\"]"`. The custom decoder unwraps these
///    into real Swift arrays (``outcomes``, ``outcomePrices``, ``clobTokenIds``).
/// 2. **No top-level category.** Categorization lives on the nested events; this
///    model surfaces a best-effort ``category`` from the first event's title.
public struct PMMarket: Codable, Sendable, Hashable, Identifiable {
    /// The market's Gamma id.
    public let id: String
    /// The market question, e.g. "Will USA win the 2026 FIFA World Cup?".
    public let question: String
    /// The on-chain condition id (`0x…`).
    public let conditionId: String
    /// URL slug.
    public let slug: String
    /// Resolution criteria / description text, if present.
    public let description: String?
    /// Resolution end date (parsed from an ISO-8601 string), if present.
    public let endDate: Date?
    /// Whether the market is closed.
    public let closed: Bool
    /// Whether the market is active.
    public let active: Bool
    /// Total traded volume.
    public let volume: PMDecimal?
    /// Available liquidity.
    public let liquidity: PMDecimal?
    /// Outcome labels, e.g. `["Yes", "No"]` (unwrapped from a JSON string).
    public let outcomes: [String]
    /// Outcome prices in `0...1`, aligned with ``outcomes`` (unwrapped from a JSON string).
    public let outcomePrices: [PMDecimal]
    /// CLOB token ids, aligned with ``outcomes`` (unwrapped from a JSON string).
    /// Pass these to ``ClobService`` to fetch live order books.
    public let clobTokenIds: [String]
    /// Best-effort category derived from the first nested event's title. Gamma
    /// has no top-level category field, so this may be `nil`.
    public let category: String?
    /// The nested events this market belongs to, if present.
    public let events: [PMEvent]?

    private enum CodingKeys: String, CodingKey {
        case id, question, conditionId, slug, description, endDate
        case closed, active, volume, liquidity
        case outcomes, outcomePrices, clobTokenIds, events
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.question = try c.decodeIfPresent(String.self, forKey: .question) ?? ""
        self.conditionId = try c.decodeIfPresent(String.self, forKey: .conditionId) ?? ""
        self.slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.closed = try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false
        self.active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? false
        self.volume = try c.decodeIfPresent(PMDecimal.self, forKey: .volume)
        self.liquidity = try c.decodeIfPresent(PMDecimal.self, forKey: .liquidity)

        if let raw = try c.decodeIfPresent(String.self, forKey: .endDate) {
            self.endDate = PMMarket.parseDate(raw)
        } else {
            self.endDate = nil
        }

        self.outcomes = PMMarket.unwrapStringArray(String.self, in: c, forKey: .outcomes)
        self.outcomePrices = PMMarket.unwrapStringArray(PMDecimal.self, in: c, forKey: .outcomePrices)
        self.clobTokenIds = PMMarket.unwrapStringArray(String.self, in: c, forKey: .clobTokenIds)

        let events = try c.decodeIfPresent([PMEvent].self, forKey: .events)
        self.events = events
        self.category = events?.first?.title
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(question, forKey: .question)
        try c.encode(conditionId, forKey: .conditionId)
        try c.encode(slug, forKey: .slug)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(closed, forKey: .closed)
        try c.encode(active, forKey: .active)
        try c.encodeIfPresent(volume, forKey: .volume)
        try c.encodeIfPresent(liquidity, forKey: .liquidity)
        if let endDate {
            try c.encode(PMMarket.formatDate(endDate), forKey: .endDate)
        }
        // Re-encode the JSON-string arrays in Gamma's wire shape so round-trips
        // produce the same representation we decoded from.
        try c.encode(PMMarket.encodeStringArray(outcomes), forKey: .outcomes)
        try c.encode(PMMarket.encodeStringArray(outcomePrices.map { "\($0.value)" }), forKey: .outcomePrices)
        try c.encode(PMMarket.encodeStringArray(clobTokenIds), forKey: .clobTokenIds)
        try c.encodeIfPresent(events, forKey: .events)
    }

    // MARK: Decoding helpers

    /// Decodes a Gamma JSON-encoded string array. The wire value is a `String`
    /// containing a JSON array (e.g. `"[\"Yes\",\"No\"]"`); we decode the outer
    /// string then JSON-decode the inner array. Defensively also accepts a real
    /// array. Returns `[]` when absent or malformed.
    private static func unwrapStringArray<T: Decodable, K: CodingKey>(
        _ element: T.Type,
        in container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> [T] {
        if let raw = try? container.decode(String.self, forKey: key),
           let data = raw.data(using: .utf8),
           let parsed = try? PMJSON.decoder.decode([T].self, from: data) {
            return parsed
        }
        // Defensive: already an array on the wire.
        if let direct = try? container.decode([T].self, forKey: key) {
            return direct
        }
        return []
    }

    /// Serializes a `[String]` back into a Gamma JSON-string array.
    private static func encodeStringArray(_ values: [String]) -> String {
        if let data = try? PMJSON.encoder.encode(values),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "[]"
    }

    // MARK: Date parsing

    /// Parses an ISO-8601 internet date-time string, with and without fractional
    /// seconds. `ISO8601DateFormatter` is not `Sendable`, so formatters are built
    /// per call rather than cached in a static.
    static func parseDate(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    /// Formats a `Date` back to an ISO-8601 internet date-time string for encoding.
    static func formatDate(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}

/// A Polymarket event (a grouping of related markets), as returned nested inside
/// markets or by the Gamma `/events` endpoint.
public struct PMEvent: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let ticker: String?
    public let slug: String?
    public let title: String?
    public let description: String?
    public let endDate: Date?
    public let closed: Bool?
    public let active: Bool?
    /// Nested markets (present on the `/events` endpoint; usually absent when an
    /// event is itself nested inside a market).
    public let markets: [PMMarket]?

    private enum CodingKeys: String, CodingKey {
        case id, ticker, slug, title, description, endDate, closed, active, markets
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.ticker = try c.decodeIfPresent(String.self, forKey: .ticker)
        self.slug = try c.decodeIfPresent(String.self, forKey: .slug)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        if let raw = try c.decodeIfPresent(String.self, forKey: .endDate) {
            self.endDate = PMMarket.parseDate(raw)
        } else {
            self.endDate = nil
        }
        self.closed = try c.decodeIfPresent(Bool.self, forKey: .closed)
        self.active = try c.decodeIfPresent(Bool.self, forKey: .active)
        self.markets = try c.decodeIfPresent([PMMarket].self, forKey: .markets)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(ticker, forKey: .ticker)
        try c.encodeIfPresent(slug, forKey: .slug)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        // Mirror the wire format: ISO-8601 string, not a numeric timestamp.
        if let endDate {
            try c.encode(PMMarket.formatDate(endDate), forKey: .endDate)
        }
        try c.encodeIfPresent(closed, forKey: .closed)
        try c.encodeIfPresent(active, forKey: .active)
        try c.encodeIfPresent(markets, forKey: .markets)
    }
}

// MARK: - Service

/// Read-only client for Polymarket's Gamma metadata API.
public struct GammaService: Sendable {
    let client: PMClient

    public init(client: PMClient) {
        self.client = client
    }

    /// Fetches one page of markets.
    ///
    /// - Parameters:
    ///   - closed: filter by closed state. Pass `false` for open markets.
    ///   - limit: page size (Gamma caps this server-side).
    ///   - offset: pagination offset.
    public func markets(closed: Bool = false, limit: Int = 100, offset: Int = 0) async throws -> [PMMarket] {
        let url = try await client.gammaURL(path: "/markets", query: [
            URLQueryItem(name: "closed", value: closed ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
        return try await client.get([PMMarket].self, url)
    }

    /// Walks the `/markets` endpoint to gather all open markets, paginating by
    /// `pageLimit` until a short/empty page or `maxPages` is reached.
    ///
    /// `maxPages` is a safety valve against runaway pagination.
    public func allOpenMarkets(pageLimit: Int = 500, maxPages: Int = 40) async throws -> [PMMarket] {
        var all: [PMMarket] = []
        var offset = 0
        for _ in 0..<maxPages {
            let page = try await markets(closed: false, limit: pageLimit, offset: offset)
            all.append(contentsOf: page)
            if page.count < pageLimit { break }
            offset += pageLimit
        }
        return all
    }

    /// Fetches one page of events.
    public func events(closed: Bool = false, limit: Int = 100, offset: Int = 0) async throws -> [PMEvent] {
        let url = try await client.gammaURL(path: "/events", query: [
            URLQueryItem(name: "closed", value: closed ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
        return try await client.get([PMEvent].self, url)
    }
}
