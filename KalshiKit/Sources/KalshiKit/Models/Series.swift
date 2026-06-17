import Foundation

/// A Kalshi series: a recurring family of events sharing a template
/// (e.g. "Will the high temperature in NYC exceed X°F today?").
public struct Series: Codable, Sendable, Hashable, Identifiable {
    public var ticker: String
    public var title: String
    public var category: String?
    public var frequency: String?
    public var tags: [String]?
    public var contractUrl: String?
    public var feeType: String?

    /// Natural identity is the series ticker.
    public var id: String { ticker }

    public init(
        ticker: String,
        title: String,
        category: String? = nil,
        frequency: String? = nil,
        tags: [String]? = nil,
        contractUrl: String? = nil,
        feeType: String? = nil
    ) {
        self.ticker = ticker
        self.title = title
        self.category = category
        self.frequency = frequency
        self.tags = tags
        self.contractUrl = contractUrl
        self.feeType = feeType
    }
}

/// Single-series endpoint envelope (`GET /series/{ticker}`).
public struct SeriesResponse: Codable, Sendable, Hashable {
    public var series: Series

    public init(series: Series) {
        self.series = series
    }
}
