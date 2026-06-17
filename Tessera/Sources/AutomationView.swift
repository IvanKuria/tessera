import SwiftUI
import KalshiKit

/// Management surface for the ambient + flagship features: price alerts and
/// synthetic stop-loss / take-profit triggers. Intentionally simple — the value
/// is in the engines; this is the control panel.
struct AutomationView: View {
    var alerts: AlertEngine
    var triggers: TriggerEngine

    var body: some View {
        TabView {
            AlertsTab(engine: alerts)
                .tabItem { Label("Alerts", systemImage: "bell") }
            TriggersTab(engine: triggers)
                .tabItem { Label("Triggers", systemImage: "bolt.shield") }
        }
        .frame(minWidth: 460, minHeight: 420)
        .preferredColorScheme(.light)
    }
}

// MARK: - Alerts

private struct AlertsTab: View {
    var engine: AlertEngine

    @State private var ticker = ""
    @State private var label = ""
    @State private var threshold = 50
    @State private var upward = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            connectionBadge(engine.connection)

            List {
                ForEach(engine.rules) { rule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rule.label.isEmpty ? rule.marketTicker : rule.label).font(.headline)
                            Text("\(rule.marketTicker) · \(rule.crossesUpward ? "≥" : "≤") \(rule.thresholdCents)¢")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { rule.enabled },
                            set: { engine.setEnabled($0, for: rule) }
                        )).labelsHidden()
                        Button(role: .destructive) { engine.removeRule(rule) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
                if engine.rules.isEmpty {
                    Text("No alerts yet.").foregroundStyle(.secondary)
                }
            }

            addForm
        }
        .padding()
    }

    private var addForm: some View {
        GroupBox("New alert") {
            Grid(alignment: .leading) {
                GridRow {
                    Text("Market"); TextField("e.g. KXNBA-…", text: $ticker)
                }
                GridRow {
                    Text("Label"); TextField("optional", text: $label)
                }
                GridRow {
                    Text("Notify when")
                    Picker("", selection: $upward) {
                        Text("rises to ≥").tag(true)
                        Text("falls to ≤").tag(false)
                    }.labelsHidden().pickerStyle(.segmented)
                }
                GridRow {
                    Text("Threshold")
                    Stepper("\(threshold)¢", value: $threshold, in: 1...99)
                }
            }
            Button("Add alert") {
                let rule = AlertRule(
                    marketTicker: ticker.trimmingCharacters(in: .whitespaces),
                    label: label.isEmpty ? ticker : label,
                    thresholdCents: threshold,
                    crossesUpward: upward
                )
                guard !rule.marketTicker.isEmpty else { return }
                engine.addRule(rule)
                ticker = ""; label = ""
            }.disabled(ticker.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

// MARK: - Triggers

private struct TriggersTab: View {
    var engine: TriggerEngine

    @State private var ticker = ""
    @State private var label = ""
    @State private var threshold = 50
    @State private var upward = false   // stop-loss default: fire when price falls
    @State private var count = 1
    @State private var limit = 50
    @State private var sell = true      // exit = sell

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Triggers run only while Tessera is open. They place a real limit order when the price crosses.")
                .font(.caption).foregroundStyle(.orange)
            connectionBadge(engine.connection)

            List {
                ForEach(engine.triggers) { t in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(t.label.isEmpty ? t.marketTicker : t.label).font(.headline)
                            Text("\(t.marketTicker) · \(t.crossesUpward ? "≥" : "≤") \(t.thresholdCents)¢ → \(t.action == .sell ? "SELL" : "BUY") \(t.count) \(t.side == .yes ? "YES" : "NO") @ \(t.limitCents)¢")
                                .font(.caption).foregroundStyle(.secondary)
                            if let msg = t.lastErrorMessage {
                                Text(msg).font(.caption2).foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        Text(t.state.rawValue).font(.caption.monospaced())
                            .foregroundStyle(stateColor(t.state))
                        if t.state != .armed {
                            Button("Re-arm") { engine.rearm(t) }.buttonStyle(.borderless)
                        }
                        Button(role: .destructive) { engine.remove(t) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
                if engine.triggers.isEmpty {
                    Text("No triggers yet.").foregroundStyle(.secondary)
                }
            }

            addForm
        }
        .padding()
    }

    private var addForm: some View {
        GroupBox("New trigger") {
            Grid(alignment: .leading) {
                GridRow { Text("Market"); TextField("e.g. KXNBA-…", text: $ticker) }
                GridRow { Text("Label"); TextField("optional", text: $label) }
                GridRow {
                    Text("Fire when")
                    Picker("", selection: $upward) {
                        Text("rises ≥ (take-profit)").tag(true)
                        Text("falls ≤ (stop-loss)").tag(false)
                    }.labelsHidden()
                }
                GridRow { Text("Threshold"); Stepper("\(threshold)¢", value: $threshold, in: 1...99) }
                GridRow {
                    Text("Then")
                    Picker("", selection: $sell) {
                        Text("SELL (exit)").tag(true)
                        Text("BUY").tag(false)
                    }.labelsHidden().pickerStyle(.segmented)
                }
                GridRow { Text("Count"); Stepper("\(count)", value: $count, in: 1...10000) }
                GridRow { Text("Limit price"); Stepper("\(limit)¢", value: $limit, in: 1...99) }
            }
            Button("Arm trigger") {
                let t = SyntheticTrigger(
                    marketTicker: ticker.trimmingCharacters(in: .whitespaces),
                    label: label.isEmpty ? ticker : label,
                    thresholdCents: threshold,
                    crossesUpward: upward,
                    action: sell ? .sell : .buy,
                    side: .yes,
                    count: count,
                    limitCents: limit
                )
                guard !t.marketTicker.isEmpty else { return }
                engine.add(t)
                ticker = ""; label = ""
            }.disabled(ticker.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func stateColor(_ s: TriggerState) -> Color {
        switch s {
        case .armed: return .blue
        case .firing: return .orange
        case .filled: return .green
        case .cancelled: return .secondary
        case .error: return .red
        }
    }
}

// MARK: - Shared

private func connectionBadge(_ state: SocketConnectionState) -> some View {
    let (text, color): (String, Color) = switch state {
    case .connected: ("Live", .green)
    case .connecting: ("Connecting…", .orange)
    case .disconnected: ("Offline", .secondary)
    }
    return HStack(spacing: 6) {
        Circle().fill(color).frame(width: 8, height: 8)
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
