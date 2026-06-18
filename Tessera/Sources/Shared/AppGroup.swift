import Foundation

/// Shared storage boundary between the main app and the WidgetKit extension.
///
/// A widget runs in its **own sandboxed process** and cannot read the app's
/// Application Support directory. The two share data through an **App Group**
/// container. This type resolves that container and round-trips a compact odds
/// snapshot (not the full event blob — keep widget decode cheap).
///
/// Resilience: if the App Group entitlement isn't provisioned yet (e.g. local
/// unsigned dev builds before the signing cutover), the container URL is `nil`;
/// we fall back to Application Support so the app keeps working. The widget will
/// simply show placeholder data until a signed build wires the real container.
enum AppGroup {
    /// Must match the `com.apple.security.application-groups` entitlement on BOTH
    /// the app and the widget target in `project.yml`.
    static let identifier = "group.app.tessera"

    /// The shared container directory, or an Application Support fallback.
    static var containerURL: URL {
        if let shared = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) {
            return shared
        }
        // Fallback for unprovisioned/unsigned dev builds.
        return URL.applicationSupportDirectory.appending(path: "Tessera")
    }

    /// File the app writes and the widget reads.
    static var widgetSnapshotURL: URL {
        containerURL.appending(path: "widget-odds.json")
    }

    /// File the synthetic-order engine persists its armed triggers to.
    static var triggersURL: URL {
        containerURL.appending(path: "triggers.json")
    }

    /// File the alert engine persists its rules to.
    static var alertRulesURL: URL {
        containerURL.appending(path: "alert-rules.json")
    }

    /// File the scanner persists its user settings to.
    static var scannerSettingsURL: URL {
        containerURL.appending(path: "scanner-settings.json")
    }

    /// File the scanner's forward paper ledger persists to.
    static var scannerPaperURL: URL {
        containerURL.appending(path: "scanner-paper.json")
    }

    /// File the scanner persists its explicitly-tracked opportunity ids to.
    static var scannerTrackedURL: URL {
        containerURL.appending(path: "scanner-tracked.json")
    }

    /// File the scanner persists its last daily-digest date to (cadence cap).
    static var scannerDigestURL: URL {
        containerURL.appending(path: "scanner-digest.json")
    }

    /// Reads and decodes a Codable value from a shared file, or `nil` if absent
    /// or unreadable. Never throws — shared-state reads should degrade quietly.
    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Encodes and atomically writes a Codable value to a shared file. Creates the
    /// container directory if needed. Returns `false` on failure (non-fatal).
    @discardableResult
    static func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

/// One row of the widget odds snapshot — the minimum a glanceable widget needs.
struct WidgetOutcome: Codable, Identifiable, Hashable, Sendable {
    var id: String          // market ticker
    var title: String       // event/outcome label
    var percent: Int        // implied probability 0…100
}

/// The compact snapshot the app writes for the widget after each refresh.
struct WidgetSnapshot: Codable, Hashable, Sendable {
    var outcomes: [WidgetOutcome]
    var updated: Date

    static let placeholder = WidgetSnapshot(
        outcomes: [
            WidgetOutcome(id: "SAMPLE-1", title: "Will it rain in NYC today?", percent: 62),
            WidgetOutcome(id: "SAMPLE-2", title: "Fed cuts rates this meeting?", percent: 18),
            WidgetOutcome(id: "SAMPLE-3", title: "Home team wins tonight?", percent: 47),
        ],
        updated: .distantPast
    )
}
