import Foundation

/// A chart-ready OHLC candle for a single focused market. Prices are in **cents**
/// (0…100, = implied probability). `id` is a stable bar index so SwiftUI Charts
/// reuses marks across renders (smooth hover).
struct CandleVM: Identifiable, Equatable, Sendable {
    let id: Int
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    let yesBid: Double?
    let yesAsk: Double?

    var isUp: Bool { close >= open }

    /// Change vs open, in cents (for the hover tooltip).
    var change: Double { close - open }
}

/// Whether the detail chart shows the probability line(s) or candlesticks.
enum ChartMode { case line, candles }
