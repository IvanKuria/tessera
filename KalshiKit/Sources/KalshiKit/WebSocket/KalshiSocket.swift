import Foundation

/// Real-time market-data client over Kalshi's WebSocket feed.
///
/// Lifecycle: call `events()` to get the stream, `connect()` to start, and
/// `subscribe(to:markets:)` to register interest. The actor owns one
/// `URLSessionWebSocketTask`, auto-reconnects with exponential backoff+jitter,
/// and **resubscribes** all registered subscriptions on every (re)connect, so
/// callers subscribe once and keep consuming across drops. Errors never end the
/// stream — they surface as `.disconnected` and the loop retries until
/// `disconnect()`.
///
/// Market-data channels work without auth; pass a `signer` to also sign the
/// handshake for user channels (fills/positions/orders).
public actor KalshiSocket {
    public typealias Events = AsyncStream<SocketEvent>

    private let environment: KalshiEnvironment
    private let signer: (any RequestSigning)?
    private let urlSession: URLSession
    private let backoff = Backoff(maxRetries: .max, base: 0.5, factor: 2, maxDelay: 30, jitterFraction: 0.5)
    private let pingInterval: Duration

    private var task: URLSessionWebSocketTask?
    private var runner: Task<Void, Never>?
    private var pinger: Task<Void, Never>?
    private var continuation: Events.Continuation?
    private var nextCommandId = 1
    private var desired: [Subscription] = []
    private var shouldRun = false
    /// True once the first message of the current connection has arrived, which
    /// is when the handshake is genuinely confirmed (resume() returns before it).
    private var announced = false

    /// Current connection state, suitable for a "Live / Reconnecting / Offline" badge.
    public private(set) var connectionState: SocketConnectionState = .disconnected

    private struct Subscription: Sendable, Hashable {
        let channels: [SocketChannel]
        let marketTickers: [String]
    }

    public init(
        environment: KalshiEnvironment = .production,
        signer: (any RequestSigning)? = nil,
        urlSession: URLSession = .shared,
        pingInterval: Duration = .seconds(30)
    ) {
        self.environment = environment
        self.signer = signer
        self.urlSession = urlSession
        self.pingInterval = pingInterval
    }

    /// Returns the event stream. Single-consumer: a second call replaces the first.
    public func events() -> Events {
        let (stream, cont) = Events.makeStream(bufferingPolicy: .bufferingNewest(512))
        continuation = cont
        return stream
    }

    /// Starts connecting (idempotent). Safe to call before or after `events()`.
    public func connect() {
        guard !shouldRun else { return }
        shouldRun = true
        runner = Task { await self.runLoop() }
    }

    /// Registers a subscription. Sent immediately if connected, and (re)sent on
    /// every future (re)connect.
    public func subscribe(to channels: [SocketChannel], markets: [String]) async {
        let sub = Subscription(channels: channels, marketTickers: markets)
        desired.append(sub)
        // Send optimistically whenever a task exists; if the handshake later
        // fails, the run loop reconnects and resubscribes everything.
        if task != nil {
            do { try await send(sub) }
            catch { emit(.serverError("subscribe failed: \(error)")) }
        }
    }

    /// Stops the client and tears down the socket. The stream stops emitting.
    public func disconnect() {
        shouldRun = false
        pinger?.cancel(); pinger = nil
        task?.cancel(with: .goingAway, reason: nil); task = nil
        runner?.cancel(); runner = nil
        connectionState = .disconnected
        continuation?.finish()
    }

    // MARK: - Connection loop

    private func runLoop() async {
        var attempt = 0
        while shouldRun && !Task.isCancelled {
            connectionState = .connecting
            do {
                try await openAndPump()        // returns only when the socket closes
                attempt = 0                    // a clean close resets backoff
            } catch is CancellationError {
                break
            } catch {
                emit(.disconnected(reason: "\(error)"))
            }
            connectionState = .disconnected
            guard shouldRun && !Task.isCancelled else { break }
            let delay = backoff.delay(forAttempt: attempt)
            attempt += 1
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func openAndPump() async throws {
        var request = URLRequest(url: environment.webSocketURL)
        request.setValue(KalshiKit.userAgent, forHTTPHeaderField: "User-Agent")
        if let signer {
            // Sign the handshake the same way as REST: ts + GET + ws path (no query).
            let ts = Int64(Date().timeIntervalSince1970 * 1000)
            let headers = try signer.authHeaders(method: "GET", path: environment.webSocketURL.path, timestampMs: ts)
            for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        }

        let socket = urlSession.webSocketTask(with: request)
        task = socket
        announced = false
        socket.resume()

        // (Re)subscribe everything registered so far. A handshake rejection
        // (e.g. HTTP 401 for an unauthenticated market-data upgrade) surfaces
        // here or on the first receive() and bubbles up to trigger a reconnect.
        for sub in desired { try await send(sub) }
        startPinger()
        defer { pinger?.cancel(); pinger = nil }

        // Pump messages until the socket throws (close/error) or we're cancelled.
        while shouldRun && !Task.isCancelled {
            let message = try await socket.receive()
            if !announced {
                announced = true
                connectionState = .connected
                emit(.connected)   // only now is the handshake truly confirmed
            }
            switch message {
            case .string(let text): handle(Data(text.utf8))
            case .data(let data): handle(data)
            @unknown default: break
            }
        }
    }

    private func startPinger() {
        pinger?.cancel()
        let interval = pingInterval
        pinger = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                await self.ping()
            }
        }
    }

    /// Sends a WebSocket ping; a failure cancels the socket so `receive()` throws
    /// and the run loop reconnects.
    private func ping() async {
        guard let socket = task else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            socket.sendPing { [weak self] error in
                if error != nil {
                    Task { await self?.failSocket() }
                }
                cont.resume()
            }
        }
    }

    private func failSocket() {
        task?.cancel(with: .abnormalClosure, reason: nil)
    }

    // MARK: - Send

    private func send(_ sub: Subscription) async throws {
        guard let socket = task else { return }
        let id = nextCommandId
        nextCommandId += 1
        let command = SocketCommand(
            id: id,
            cmd: "subscribe",
            params: .init(
                channels: sub.channels.map(\.rawValue),
                marketTickers: sub.marketTickers.isEmpty ? nil : sub.marketTickers
            )
        )
        let data = try KalshiJSON.encoder.encode(command)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    // MARK: - Receive

    private func handle(_ data: Data) {
        let decoder = KalshiJSON.decoder
        guard let probe = try? decoder.decode(SocketProbe.self, from: data) else {
            emit(.unknown(type: "undecodable"))
            return
        }
        switch probe.type {
        case "subscribed":
            let env = try? decoder.decode(SocketEnvelope<SocketSubscribed>.self, from: data)
            emit(.subscribed(env?.msg ?? SocketSubscribed()))
        case "ticker", "ticker_v2":
            if let m = (try? decoder.decode(SocketEnvelope<TickerUpdate>.self, from: data))?.msg {
                emit(.ticker(m))
            }
        case "orderbook_snapshot", "orderbook_delta":
            if let m = (try? decoder.decode(SocketEnvelope<OrderbookUpdate>.self, from: data))?.msg {
                emit(.orderbook(m))
            }
        case "trade":
            if let m = (try? decoder.decode(SocketEnvelope<TradeUpdate>.self, from: data))?.msg {
                emit(.trade(m))
            }
        case "error":
            emit(.serverError(String(decoding: data, as: UTF8.self)))
        case "ok", "pong":
            break
        default:
            emit(.unknown(type: probe.type))
        }
    }

    private func emit(_ event: SocketEvent) {
        continuation?.yield(event)
    }
}
