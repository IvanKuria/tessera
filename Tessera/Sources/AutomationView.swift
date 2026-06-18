import SwiftUI
import KalshiKit

/// Control panel for price alerts and synthetic stop-loss / take-profit triggers.
/// Themed to match the rest of Tessera; the value is in the engines.
struct AutomationView: View {
    var alerts: AlertEngine
    var triggers: TriggerEngine

    enum Tab: String, CaseIterable { case alerts = "Alerts", triggers = "Triggers" }
    @State private var tab: Tab = .alerts

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button { withAnimation(.easeOut(duration: 0.15)) { tab = t } } label: {
                        Text(t.rawValue)
                            .font(Theme.ui(12, tab == t ? .semibold : .regular))
                            .foregroundStyle(tab == t ? Theme.text : Theme.textSecondary)
                            .padding(.horizontal, 18).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7).fill(tab == t ? Theme.surface : Color.clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.subtle))
            .padding(.vertical, 12)

            Divider().overlay(Theme.divider)

            switch tab {
            case .alerts:   AlertsTab(engine: alerts)
            case .triggers: TriggersTab(engine: triggers)
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(Theme.bg)
        .preferredColorScheme(.light)
    }
}

// MARK: - Alerts

private struct AlertsTab: View {
    var engine: AlertEngine

    @State private var ticker = ""
    @State private var label = ""
    @State private var threshold = 50.0
    @State private var upward = true
    @State private var editingID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AutomationHeader(
                    title: "Price Alerts",
                    subtitle: "Get a native notification when a market crosses your level. Needs a connected key to run.",
                    connection: engine.connection
                )

                composer

                if engine.rules.isEmpty {
                    AutomationEmpty(icon: "bell", text: "No alerts yet — add one above, or use the Alert button on any chart.")
                } else {
                    ForEach(engine.rules) { rule in row(rule) }
                }
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }

    // New / edit composer
    private var composer: some View {
        AutomationCard(title: editingID == nil ? "New alert" : "Edit alert") {
            VStack(spacing: 12) {
                LabeledField("Market") {
                    ThemedField("e.g. KXNBA-…", text: $ticker)
                }
                LabeledField("Label") {
                    ThemedField("optional", text: $label)
                }
                LabeledField("Notify when") {
                    Segmented(options: ["Rises to ≥": true, "Falls to ≤": false], order: ["Rises to ≥", "Falls to ≤"], selection: $upward)
                }
                LabeledField("Threshold") {
                    CentsStepper(value: $threshold)
                    Spacer()
                }
                HStack {
                    if editingID != nil {
                        Button("Cancel") { clearForm() }.buttonStyle(.plain)
                            .font(Theme.ui(12)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    PrimaryButton(editingID == nil ? "Add alert" : "Save changes", enabled: !trimmedTicker.isEmpty) {
                        let rule = AlertRule(
                            id: editingID ?? UUID(),
                            marketTicker: trimmedTicker,
                            label: label.isEmpty ? trimmedTicker : label,
                            thresholdCents: Int(threshold),
                            crossesUpward: upward
                        )
                        if editingID == nil { engine.addRule(rule) } else { engine.updateRule(rule) }
                        clearForm()
                    }
                }
            }
        }
    }

    private func row(_ rule: AlertRule) -> some View {
        AutomationRow(
            enabled: rule.enabled,
            title: rule.label.isEmpty ? rule.marketTicker : rule.label,
            subtitle: "\(rule.marketTicker)  ·  \(rule.crossesUpward ? "≥" : "≤") \(rule.thresholdCents)¢",
            tint: rule.crossesUpward ? Theme.yes : Theme.no,
            onToggle: { engine.setEnabled($0, for: rule) },
            onEdit: {
                editingID = rule.id
                ticker = rule.marketTicker
                label = rule.label
                threshold = Double(rule.thresholdCents)
                upward = rule.crossesUpward
            },
            onDelete: { engine.removeRule(rule); if editingID == rule.id { clearForm() } }
        )
    }

    private var trimmedTicker: String { ticker.trimmingCharacters(in: .whitespaces) }
    private func clearForm() { editingID = nil; ticker = ""; label = ""; threshold = 50; upward = true }
}

// MARK: - Triggers

private struct TriggersTab: View {
    var engine: TriggerEngine

    @State private var ticker = ""
    @State private var label = ""
    @State private var threshold = 50.0
    @State private var upward = false
    @State private var count = 1.0
    @State private var limit = 50.0
    @State private var sell = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AutomationHeader(
                    title: "Triggers",
                    subtitle: "Place a real limit order when a market crosses your level. Runs only while Tessera is open.",
                    connection: engine.connection,
                    warn: true
                )

                composer

                if engine.triggers.isEmpty {
                    AutomationEmpty(icon: "bolt.shield", text: "No triggers yet. A trigger fires a real order — set one up above.")
                } else {
                    ForEach(engine.triggers) { t in row(t) }
                }
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }

    private var composer: some View {
        AutomationCard(title: "New trigger") {
            VStack(spacing: 12) {
                LabeledField("Market") { ThemedField("e.g. KXNBA-…", text: $ticker) }
                LabeledField("Label") { ThemedField("optional", text: $label) }
                LabeledField("Fire when") {
                    Segmented(options: ["Rises ≥ (take-profit)": true, "Falls ≤ (stop-loss)": false],
                              order: ["Rises ≥ (take-profit)", "Falls ≤ (stop-loss)"], selection: $upward)
                }
                LabeledField("Threshold") { CentsStepper(value: $threshold); Spacer() }
                LabeledField("Then") {
                    Segmented(options: ["Sell (exit)": true, "Buy": false], order: ["Sell (exit)", "Buy"], selection: $sell)
                }
                LabeledField("Count") { PlainStepper(value: $count, range: 1...10000, suffix: ""); Spacer() }
                LabeledField("Limit price") { CentsStepper(value: $limit); Spacer() }
                HStack {
                    Spacer()
                    PrimaryButton("Arm trigger", enabled: !trimmedTicker.isEmpty) {
                        let t = SyntheticTrigger(
                            marketTicker: trimmedTicker,
                            label: label.isEmpty ? trimmedTicker : label,
                            thresholdCents: Int(threshold),
                            crossesUpward: upward,
                            action: sell ? .sell : .buy,
                            side: .yes,
                            count: Int(count),
                            limitCents: Int(limit)
                        )
                        engine.add(t)
                        ticker = ""; label = ""
                    }
                }
            }
        }
    }

    private func row(_ t: SyntheticTrigger) -> some View {
        AutomationCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(t.label.isEmpty ? t.marketTicker : t.label)
                        .font(Theme.ui(14, .semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(t.state.rawValue.uppercased())
                        .font(Theme.num(9.5, .bold)).tracking(0.6)
                        .foregroundStyle(stateColor(t.state))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(stateColor(t.state).opacity(0.12)))
                }
                Text("\(t.marketTicker)  ·  \(t.crossesUpward ? "≥" : "≤") \(t.thresholdCents)¢ → \(t.action == .sell ? "SELL" : "BUY") \(t.count) \(t.side == .yes ? "YES" : "NO") @ \(t.limitCents)¢")
                    .font(Theme.num(11.5)).foregroundStyle(Theme.textSecondary)
                if let msg = t.lastErrorMessage {
                    Text(msg).font(Theme.ui(11)).foregroundStyle(Theme.no)
                }
                HStack(spacing: 10) {
                    Spacer()
                    if t.state != .armed {
                        Button("Re-arm") { engine.rearm(t) }.buttonStyle(.plain)
                            .font(Theme.ui(12, .semibold)).foregroundStyle(Theme.yes)
                    }
                    Button { engine.remove(t) } label: {
                        Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var trimmedTicker: String { ticker.trimmingCharacters(in: .whitespaces) }

    private func stateColor(_ s: TriggerState) -> Color {
        switch s {
        case .armed:     return Theme.info
        case .firing:    return Theme.text
        case .filled:    return Theme.yes
        case .cancelled: return Theme.textTertiary
        case .error:     return Theme.no
        }
    }
}

// MARK: - Shared themed components

private struct AutomationHeader: View {
    let title: String
    let subtitle: String
    let connection: SocketConnectionState
    var warn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(Theme.condensed(24, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                connectionBadge(connection)
            }
            Text(subtitle).font(Theme.ui(12)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AutomationCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(Theme.ui(12, .semibold)).foregroundStyle(Theme.textSecondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1)))
    }
}

private struct AutomationRow: View {
    let enabled: Bool
    let title: String
    let subtitle: String
    let tint: Color
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(enabled ? tint : Theme.textTertiary.opacity(0.4)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.ui(14, .semibold)).foregroundStyle(enabled ? Theme.text : Theme.textSecondary).lineLimit(1)
                Text(subtitle).font(Theme.num(11.5)).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { enabled }, set: onToggle)).labelsHidden().toggleStyle(.switch).controlSize(.small)
            Button(action: onEdit) {
                Image(systemName: "pencil").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }.buttonStyle(.plain)
            Button(action: onDelete) {
                Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }.buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1)))
    }
}

private struct AutomationEmpty: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(Theme.textTertiary)
            Text(text).font(Theme.ui(12.5)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) { self.label = label; self.content = content() }
    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(Theme.ui(12, .medium)).foregroundStyle(Theme.textSecondary)
                .frame(width: 92, alignment: .leading)
            content
        }
    }
}

private struct ThemedField: View {
    let placeholder: String
    @Binding var text: String
    init(_ placeholder: String, text: Binding<String>) { self.placeholder = placeholder; _text = text }
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain).font(Theme.ui(13)).foregroundStyle(Theme.text)
            .padding(.vertical, 8).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1)))
    }
}

private struct Segmented: View {
    let options: [String: Bool]
    let order: [String]
    @Binding var selection: Bool
    var body: some View {
        HStack(spacing: 0) {
            ForEach(order, id: \.self) { key in
                let value = options[key] ?? false
                Button { selection = value } label: {
                    Text(key)
                        .font(Theme.ui(12, selection == value ? .semibold : .regular))
                        .foregroundStyle(selection == value ? Theme.text : Theme.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(selection == value ? Theme.surface : Color.clear))
                }.buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.subtle))
    }
}

private struct CentsStepper: View {
    @Binding var value: Double
    var body: some View { PlainStepper(value: $value, range: 1...99, suffix: "¢") }
}

private struct PlainStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String
    var body: some View {
        HStack(spacing: 8) {
            btn("minus") { value = max(range.lowerBound, value - 1) }
            Text("\(Int(value))\(suffix)").font(Theme.num(13, .semibold)).foregroundStyle(Theme.text).frame(minWidth: 40)
            btn("plus") { value = min(range.upperBound, value + 1) }
        }
    }
    private func btn(_ s: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: s).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textSecondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.surface).overlay(Circle().stroke(Theme.border, lineWidth: 1)))
        }.buttonStyle(.plain)
    }
}

private struct PrimaryButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void
    init(_ title: String, enabled: Bool, action: @escaping () -> Void) { self.title = title; self.enabled = enabled; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.ui(12.5, .semibold)).foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Capsule().fill(Theme.yes)).opacity(enabled ? 1 : 0.45)
        }.buttonStyle(.plain).disabled(!enabled)
    }
}

private func connectionBadge(_ state: SocketConnectionState) -> some View {
    let (text, color): (String, Color) = switch state {
    case .connected:    ("Live", Theme.yes)
    case .connecting:   ("Connecting…", Theme.info)
    case .disconnected: ("Offline", Theme.textTertiary)
    }
    return HStack(spacing: 5) {
        Circle().fill(color).frame(width: 7, height: 7)
        Text(text).font(Theme.ui(11, .medium)).foregroundStyle(Theme.textSecondary)
    }
}
