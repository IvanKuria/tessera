import Foundation
import KalshiKit

/// The trading / account source of truth. Owns the user's Kalshi credentials
/// (Keychain-only), the signed client, balance, and positions. Networking is
/// performed by the `KalshiClient` actor off the main thread; this
/// `@MainActor @Observable` store shapes the result for SwiftUI.
///
/// Safety posture: defaults to the DEMO environment, the user supplies their own
/// API key, and the RSA private key is persisted ONLY in the macOS Keychain —
/// never logged, cached, or written to disk by this app.
@MainActor
@Observable
final class AccountStore {
    /// Which Kalshi backend the account talks to. Defaults to `.demo` for safety.
    enum Env: Equatable {
        case demo, production

        /// Maps to the SDK's environment.
        var kalshi: KalshiEnvironment {
            switch self {
            case .demo:       return .demo
            case .production: return .production
            }
        }

        /// Short badge label shown on the ticket ("DEMO" / "PROD").
        var badge: String {
            switch self {
            case .demo:       return "DEMO"
            case .production: return "PROD"
            }
        }
    }

    // MARK: - Observable state

    private(set) var isSignedIn: Bool = false
    private(set) var env: Env = .demo
    private(set) var balanceCents: Int?
    private(set) var positions: [MarketPosition] = []
    var lastError: String?
    private(set) var isWorking: Bool = false

    // MARK: - Private wiring

    /// The Keychain item shared with the SDK; PEM lives here and nowhere else.
    private let keychain = KeychainCredentialStore(service: "app.tessera.kalshi")
    /// Credentials held in memory for the current session (to rebuild on env change).
    private var credentials: KalshiCredentials?
    private var signer: KalshiSigner?
    private var client: KalshiClient?

    // MARK: - Shared access (for Portfolio + live WebSocket feed)

    /// The signed REST client, when signed in (read-only reuse by other stores).
    var authedClient: KalshiClient? { client }
    /// The request signer, for opening an authenticated WebSocket.
    var liveSigner: (any RequestSigning)? { signer }
    /// The active SDK environment.
    var kalshiEnvironment: KalshiEnvironment { env.kalshi }

    // MARK: - Init

    init() {
        loadFromKeychain()
    }

    /// Loads any stored credentials and builds a signed client, marking the
    /// account signed in. Does NOT make any network calls (keep init cheap and
    /// non-throwing for SwiftUI). Default environment is `.demo`.
    private func loadFromKeychain() {
        do {
            guard let creds = try keychain.load() else { return }
            let signer = try KalshiSigner(credentials: creds)
            self.credentials = creds
            self.signer = signer
            self.client = KalshiClient(environment: env.kalshi, signer: signer)
            self.isSignedIn = true
        } catch {
            // A malformed stored key shouldn't crash launch; surface it quietly.
            lastError = readable(error)
        }
    }

    // MARK: - Sign in / out

    /// Validates the PEM, persists credentials to the Keychain, builds a signed
    /// client, and refreshes the account. Returns `false` (with `lastError` set)
    /// if the PEM is invalid or the Keychain write fails.
    func signIn(keyID: String, pem: String) async -> Bool {
        let trimmedKey = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPem = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedPem.isEmpty else {
            lastError = "Enter both your Key ID and RSA private key."
            return false
        }

        isWorking = true
        defer { isWorking = false }
        lastError = nil

        let creds = KalshiCredentials(apiKeyID: trimmedKey, privateKeyPEM: trimmedPem)

        // Validate the PEM by attempting to build the signer BEFORE persisting.
        let builtSigner: KalshiSigner
        do {
            builtSigner = try KalshiSigner(credentials: creds)
        } catch {
            lastError = "That private key couldn't be read. Paste the full RSA PEM, including the BEGIN/END lines. (\(readable(error)))"
            return false
        }

        // Persist to Keychain (PEM lives only here).
        do {
            try keychain.save(creds)
        } catch {
            lastError = "Couldn't save your key to the Keychain. (\(readable(error)))"
            return false
        }

        self.credentials = creds
        self.signer = builtSigner
        self.client = KalshiClient(environment: env.kalshi, signer: builtSigner)
        self.isSignedIn = true

        await refreshAccount()
        return true
    }

    /// Clears credentials from the Keychain and tears down the session.
    func signOut() {
        try? keychain.clear()
        credentials = nil
        signer = nil
        client = nil
        isSignedIn = false
        balanceCents = nil
        positions = []
        lastError = nil
    }

    // MARK: - Environment

    /// Switches the environment, rebuilding the signer + client from the same
    /// in-memory credentials so the new backend is authenticated. Then refreshes.
    func setEnv(_ newEnv: Env) {
        guard newEnv != env else { return }
        env = newEnv

        guard let creds = credentials else { return }
        do {
            let rebuiltSigner = try KalshiSigner(credentials: creds)
            self.signer = rebuiltSigner
            self.client = KalshiClient(environment: env.kalshi, signer: rebuiltSigner)
            Task { await refreshAccount() }
        } catch {
            lastError = readable(error)
        }
    }

    // MARK: - Account data

    /// Loads balance + positions. Tolerates per-call failures into `lastError`
    /// rather than throwing, so a partial refresh still updates what it can.
    func refreshAccount() async {
        guard isSignedIn, let client else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let balance = try await client.balance()
            balanceCents = balance.balance
        } catch {
            lastError = readable(error)
        }

        do {
            let response = try await client.positions(limit: 200)
            positions = (response.marketPositions ?? []).filter { ($0.position ?? 0) != 0 }
        } catch {
            lastError = readable(error)
        }
    }

    // MARK: - Trading

    /// Places a buy/sell order. If `limitCents` is non-nil a LIMIT order is built
    /// (price on the chosen side); otherwise a MARKET order. Refreshes the
    /// account on success. Returns the SDK `Order` or the underlying error.
    /// `clientOrderId` is the server-side idempotency key. Leave it `nil` for
    /// interactive orders (a fresh UUID is generated). The synthetic-order engine
    /// passes a STABLE id derived from the trigger so an ambiguous retry after a
    /// timeout dedupes to the same order rather than firing twice.
    func placeOrder(
        marketTicker: String,
        action: OrderAction,
        side: OrderSide,
        count: Int,
        limitCents: Int?,
        clientOrderId: String? = nil
    ) async -> Result<Order, Error> {
        guard isSignedIn, let client else {
            return .failure(TradeError.notSignedIn)
        }
        guard count >= 1 else {
            return .failure(TradeError.invalidQuantity)
        }

        isWorking = true
        defer { isWorking = false }
        lastError = nil

        let orderId = clientOrderId ?? UUID().uuidString
        let request: CreateOrderRequest
        if let limitCents {
            let clamped = min(99, max(1, limitCents))
            request = CreateOrderRequest(
                ticker: marketTicker,
                action: action,
                side: side,
                count: count,
                type: "limit",
                yesPrice: side == .yes ? clamped : nil,
                noPrice: side == .no ? clamped : nil,
                // Omit time_in_force → a resting limit (GTC) by default; sending an
                // unexpected TIF value can be rejected as "invalid order".
                timeInForce: nil,
                clientOrderId: orderId,
                buyMaxCost: nil
            )
        } else {
            request = CreateOrderRequest(
                ticker: marketTicker,
                action: action,
                side: side,
                count: count,
                type: "market",
                yesPrice: nil,
                noPrice: nil,
                timeInForce: nil,
                clientOrderId: orderId,
                buyMaxCost: nil
            )
        }

        do {
            let order = try await client.createOrder(request)
            await refreshAccount()
            return .success(order)
        } catch {
            lastError = readable(error)
            return .failure(error)
        }
    }

    // MARK: - Helpers

    /// Errors local to the trading layer.
    enum TradeError: LocalizedError {
        case notSignedIn
        case invalidQuantity

        var errorDescription: String? {
            switch self {
            case .notSignedIn:     return "Connect your Kalshi API key first."
            case .invalidQuantity: return "Order quantity must be at least 1 contract."
            }
        }
    }

    private func readable(_ error: Error) -> String {
        if case let KalshiError.http(status, message, body) = error {
            // A 401 almost always means the env doesn't match where the key was made.
            if status == 401 {
                return """
                Authentication failed (401) on \(env.badge). Make sure the selected \
                environment matches where you created your API key: kalshi.com keys \
                are Production; demo.kalshi.co keys are Demo. Use the account menu to \
                switch environments. (\(message ?? "token authentication failure"))
                """
            }
            // Surface Kalshi's full error body so the real reason is visible.
            let detail = body
                .flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = (detail?.isEmpty == false) ? " — \(detail!.prefix(400))" : ""
            return "Request failed (HTTP \(status))\(message.map { ": \($0)" } ?? "")\(snippet)"
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
