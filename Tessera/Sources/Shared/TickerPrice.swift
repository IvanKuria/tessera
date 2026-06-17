import Foundation
import KalshiKit

extension TickerUpdate {
    /// Best available "current price" in integer cents for threshold comparison.
    ///
    /// The ticker feed mixes integer-cent and dollar-string encodings, so this
    /// normalizes them in priority order: last trade price → last dollars →
    /// yes bid/ask mid (cents, then dollars) → yes ask. Returns `nil` if the
    /// update carries no usable price.
    var lastCents: Int? {
        if let p = price { return p }
        if let pd = priceDollars { return pd.centsRounded }
        if let bid = yesBid, let ask = yesAsk { return (bid + ask) / 2 }
        if let bid = yesBidDollars, let ask = yesAskDollars {
            return (bid.centsRounded + ask.centsRounded) / 2
        }
        if let ask = yesAskDollars { return ask.centsRounded }
        return nil
    }
}
