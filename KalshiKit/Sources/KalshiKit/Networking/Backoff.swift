import Foundation

/// Client-side exponential backoff with jitter for retrying rate-limited (429)
/// and transient transport failures.
///
/// Kalshi sends **no** `Retry-After` / `X-RateLimit-*` headers, so retry timing
/// is purely client-driven. Delays follow `base * factor^attempt`, capped at
/// `maxDelay`, with ±`jitterFraction` randomization to avoid thundering-herd
/// retries. The randomness uses `SystemRandomNumberGenerator` (not a
/// `Date()`-seeded RNG), so tests can inject a deterministic generator.
public struct Backoff: Sendable {
    /// Maximum number of *retries* (the initial attempt is not counted).
    public let maxRetries: Int
    /// Base delay for the first retry, in seconds.
    public let base: TimeInterval
    /// Multiplier applied per attempt.
    public let factor: Double
    /// Hard ceiling on any single delay, in seconds.
    public let maxDelay: TimeInterval
    /// Fractional jitter applied symmetrically (e.g. `0.5` → ±50%).
    public let jitterFraction: Double

    /// The SDK default: 4 retries, base 0.5s, factor 2, max 8s, ±50% jitter.
    public static let `default` = Backoff(
        maxRetries: 4,
        base: 0.5,
        factor: 2,
        maxDelay: 8,
        jitterFraction: 0.5
    )

    public init(
        maxRetries: Int = 4,
        base: TimeInterval = 0.5,
        factor: Double = 2,
        maxDelay: TimeInterval = 8,
        jitterFraction: Double = 0.5
    ) {
        self.maxRetries = maxRetries
        self.base = base
        self.factor = factor
        self.maxDelay = maxDelay
        self.jitterFraction = jitterFraction
    }

    /// Computes the delay (seconds) before the given retry `attempt` (0-based:
    /// `attempt == 0` is the delay before the first retry), jittered via the
    /// supplied random generator.
    public func delay<G: RandomNumberGenerator>(forAttempt attempt: Int, using generator: inout G) -> TimeInterval {
        let raw = base * pow(factor, Double(max(0, attempt)))
        let capped = min(raw, maxDelay)
        guard jitterFraction > 0 else { return capped }
        let spread = capped * jitterFraction
        let delta = TimeInterval.random(in: -spread...spread, using: &generator)
        return max(0, capped + delta)
    }

    /// Convenience overload using the system RNG.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        var generator = SystemRandomNumberGenerator()
        return delay(forAttempt: attempt, using: &generator)
    }
}
