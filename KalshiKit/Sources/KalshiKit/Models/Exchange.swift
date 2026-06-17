import Foundation

/// Exchange-wide trading status (`GET /exchange/status`).
public struct ExchangeStatus: Codable, Sendable, Hashable {
    /// Whether the exchange is generally active.
    public var exchangeActive: Bool?
    /// Whether trading specifically is currently active.
    public var tradingActive: Bool?
    /// Raw ISO-8601 estimated resume time, if the exchange is paused.
    public var exchangeEstimatedResumeTime: String?

    /// Parsed estimated resume time.
    public var exchangeEstimatedResumeDate: Date? {
        KalshiTime.date(fromISO: exchangeEstimatedResumeTime)
    }

    public init(
        exchangeActive: Bool? = nil,
        tradingActive: Bool? = nil,
        exchangeEstimatedResumeTime: String? = nil
    ) {
        self.exchangeActive = exchangeActive
        self.tradingActive = tradingActive
        self.exchangeEstimatedResumeTime = exchangeEstimatedResumeTime
    }
}
