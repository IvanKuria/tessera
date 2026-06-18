import AppKit

/// Outbound links to Kalshi's own website. Tessera never moves money itself —
/// deposits and withdrawals happen on Kalshi (behind their KYC/banking flows),
/// so these are pure convenience links that open in the user's default browser.
enum KalshiLinks {
    /// Kalshi's funds management page (deposit / withdraw / linked accounts).
    static let manageFunds = URL(string: "https://kalshi.com/account/banking")!

    /// Opens a link in the default browser.
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
