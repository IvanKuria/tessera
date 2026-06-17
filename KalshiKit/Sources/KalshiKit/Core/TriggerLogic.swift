import Foundation

/// Direction of a synthetic stop-loss / take-profit trigger.
///
/// Kalshi has no native stop orders, so a client watches the live ticker price
/// and fires a limit order when the price crosses a user-set threshold. The
/// direction selects which side of the threshold the price must cross *into*:
///
/// - ``above``: fire when the price rises **to or above** the threshold
///   (a take-profit on a long, or a stop on a short).
/// - ``below``: fire when the price falls **to or below** the threshold
///   (a stop-loss on a long, or a take-profit on a short).
public enum TriggerDirection: Sendable {
    /// Fire when the price rises to or above the threshold.
    case above
    /// Fire when the price falls to or below the threshold.
    case below
}

/// The outcome of evaluating a single ticker tick against a trigger.
///
/// This is richer than a bare `Bool` so callers can distinguish "this tick only
/// established the baseline" from "the price is moving but has not crossed" —
/// useful for UI state and logging without re-deriving it.
public enum TriggerEvaluation: Sendable, Hashable {
    /// The first tick after (re)arming or reconnecting. No prior tick existed,
    /// so this tick only establishes the baseline and never fires.
    case armedBaseline
    /// A baseline exists and the price has not crossed the threshold this tick.
    case holding
    /// The price crossed the threshold on this tick: the order should fire now.
    case fire
}

/// Pure, edge-triggered crossing detection for synthetic stop / take-profit orders.
///
/// This is the safety-critical core of the feature: it guards real money, so it is
/// a pure function with no networking, app, or SwiftUI dependencies, making it
/// exhaustively CLI-testable and provably correct. Getting it wrong means firing
/// twice or never.
///
/// ## Edge-triggered, not level-triggered
///
/// The trigger fires on the *transition across* the threshold, not on the mere
/// *state of being past* it. A level-triggered check (`currentCents >= threshold`)
/// would re-fire on every subsequent tick while the price stays past the
/// threshold, placing duplicate orders. Instead we require the **previous** tick
/// to have been on the not-yet-crossed side and the **current** tick to have
/// reached the crossed side:
///
/// - ``TriggerDirection/above``: fire iff `previous < threshold && current >= threshold`.
/// - ``TriggerDirection/below``: fire iff `previous > threshold && current <= threshold`.
///
/// The threshold itself counts as "crossed" (`>=` / `<=`), so an exact touch fires.
/// Because the previous side is strict (`<` / `>`), a price that is already past the
/// threshold when the baseline is set will *not* fire on later ticks — it must first
/// move back to the not-yet-crossed side and then re-cross.
///
/// ## Baseline and reconnect behavior
///
/// `previousCents` is `nil` when there is no baseline yet — just (re)armed, or just
/// reconnected. The first tick after that only establishes the baseline and never
/// fires. Callers **must** reset `previousCents` to `nil` on reconnect: if the price
/// gapped across the threshold while the client was offline, we have no evidence of a
/// genuine live crossing, so we re-baseline rather than auto-fire on a stale gap.
///
/// - Parameters:
///   - previousCents: The last observed price in integer cents, or `nil` if no
///     baseline has been established yet (freshly armed or reconnected).
///   - currentCents: The new tick's price in integer cents.
///   - thresholdCents: The user-set trigger price in integer cents.
///   - direction: Whether to fire on an upward (``TriggerDirection/above``) or
///     downward (``TriggerDirection/below``) crossing.
/// - Returns: A ``TriggerEvaluation`` describing whether this tick armed the
///   baseline, is holding, or should fire.
public func evaluateTrigger(
    previousCents: Int?,
    currentCents: Int,
    thresholdCents: Int,
    direction: TriggerDirection
) -> TriggerEvaluation {
    guard let previousCents else {
        return .armedBaseline
    }

    switch direction {
    case .above:
        if previousCents < thresholdCents && currentCents >= thresholdCents {
            return .fire
        }
    case .below:
        if previousCents > thresholdCents && currentCents <= thresholdCents {
            return .fire
        }
    }

    return .holding
}

/// Convenience wrapper returning whether a trigger should fire on this tick.
///
/// Equivalent to ``evaluateTrigger(previousCents:currentCents:thresholdCents:direction:)``
/// returning ``TriggerEvaluation/fire``. See that function for the full
/// edge-trigger and reconnect/baseline semantics.
public func triggerShouldFire(
    previousCents: Int?,
    currentCents: Int,
    thresholdCents: Int,
    direction: TriggerDirection
) -> Bool {
    evaluateTrigger(
        previousCents: previousCents,
        currentCents: currentCents,
        thresholdCents: thresholdCents,
        direction: direction
    ) == .fire
}
