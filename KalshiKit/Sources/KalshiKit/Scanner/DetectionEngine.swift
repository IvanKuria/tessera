import Foundation

public enum DetectionEngine {
    public static let detectors: [any Detector.Type] = [
        MultiOutcomeLockDetector.self, LadderMonotonicityDetector.self, SpreadStaleDetector.self, BookIntegrityCheck.self
    ]
    public static func scan(_ snapshot: ScanSnapshot) -> [Opportunity] {
        ranked(detectors.flatMap { $0.scan(snapshot) }, config: snapshot.config)
    }
    /// Locks above edges; within lane sort by annualized then net-edge; below-hurdle sinks.
    public static func ranked(_ opps: [Opportunity], config: DetectorConfig) -> [Opportunity] {
        func belowHurdle(_ o: Opportunity) -> Bool { o.warnings.contains { if case .belowHurdle = $0 { return true }; return false } }
        return opps.sorted { a, b in
            if a.lane != b.lane { return a.lane == .lock }
            if belowHurdle(a) != belowHurdle(b) { return !belowHurdle(a) }
            if a.lane == .edge, a.confidence != b.confidence { return a.confidence > b.confidence }
            if a.annualizedPct != b.annualizedPct { return a.annualizedPct > b.annualizedPct }
            return a.netEdgeCents > b.netEdgeCents
        }
    }
}
