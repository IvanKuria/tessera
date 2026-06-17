import SwiftUI
import Charts
import KalshiKit

/// Implied-probability chart. Plots one colored line per outcome (like Kalshi's
/// multi-candidate view) with a legend; a single-outcome market shows one line
/// with hover scrubbing. Endpoint dots mark each line's latest value.
struct PriceChartView: View {
    let series: [DetailStore.SeriesLine]
    let isLoading: Bool
    @Binding var timeframe: DetailStore.Timeframe
    var onTimeframeChange: () -> Void = {}
    /// When set, that outcome's line is emphasized and the others fade back.
    var highlightedID: String? = nil
    var onSelectSeries: (String) -> Void = { _ in }

    private typealias Point = DetailStore.ChartPoint
    @State private var selectedDate: Date?

    /// Only emphasize when the highlighted outcome actually has a line here
    /// (outcomes outside the charted top-N leave every line at full strength).
    private var activeHighlight: String? {
        guard let h = highlightedID, series.contains(where: { $0.id == h }) else { return nil }
        return h
    }

    // Per-line emphasis driven by `activeHighlight`.
    private func lineOpacity(_ line: DetailStore.SeriesLine) -> Double {
        guard let h = activeHighlight else { return isMulti ? 0.9 : 1 }
        return h == line.id ? 1 : 0.14
    }
    private func lineWidth(_ line: DetailStore.SeriesLine) -> Double {
        guard let h = activeHighlight else { return isMulti ? 1.7 : 2 }
        return h == line.id ? 2.6 : 1.2
    }
    private func showsDot(_ line: DetailStore.SeriesLine) -> Bool {
        activeHighlight == nil || activeHighlight == line.id
    }
    private func legendOpacity(_ line: DetailStore.SeriesLine) -> Double {
        activeHighlight == nil || activeHighlight == line.id ? 1 : 0.4
    }

    /// 3+ lines = candidate chart (no fill/hover). 2 = binary Yes/No.
    private var isMulti: Bool { series.count > 2 }
    private var showLegend: Bool { series.count >= 2 }
    private var hasData: Bool { series.contains { $0.points.count >= 2 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showLegend { legend }
            chartArea.frame(height: 340)
            selector
        }
    }

    private var legend: some View {
        FlowLayout(spacing: 16, lineSpacing: 9) {
            ForEach(series) { line in
                Button { onSelectSeries(line.id) } label: {
                    HStack(spacing: 7) {
                        Circle().fill(line.color).frame(width: 10, height: 10)
                        Text(line.label)
                            .font(Theme.ui(13, highlightedID == line.id ? .semibold : .medium))
                            .foregroundStyle(Theme.text).lineLimit(1)
                        if let p = line.lastPercent {
                            Text("\(Int(p.rounded()))%").font(Theme.num(13, .semibold)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .opacity(legendOpacity(line))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var chartArea: some View {
        if hasData {
            chart
        } else if isLoading {
            placeholder { ProgressView().controlSize(.small) }
        } else {
            placeholder {
                Text("No price history").font(Theme.ui(13, .medium)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func placeholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack { content() }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Nearest point in a line to a given date.
    private func nearestPoint(_ line: DetailStore.SeriesLine, to date: Date) -> Point? {
        line.points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// Snapped crosshair date = the first line's point nearest the cursor.
    private var crosshairDate: Date? {
        guard let selectedDate, let first = series.first else { return nil }
        return nearestPoint(first, to: selectedDate)?.date
    }

    /// Lines shown in the tooltip: just the emphasized one, or all of them.
    private var tooltipLines: [DetailStore.SeriesLine] {
        if let h = activeHighlight { return series.filter { $0.id == h } }
        return series
    }

    private var chart: some View {
        Chart {
            ForEach(series) { line in
                ForEach(line.points) { p in
                    LineMark(
                        x: .value("Time", p.date),
                        y: .value("Percent", p.percent),
                        series: .value("Outcome", line.id)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(line.color.opacity(lineOpacity(line)))
                    .lineStyle(StrokeStyle(lineWidth: lineWidth(line)))
                }

            }

            if let cd = crosshairDate {
                RuleMark(x: .value("Time", cd))
                    .foregroundStyle(Theme.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        crosshairTooltip(date: cd)
                    }
                ForEach(tooltipLines) { line in
                    if let p = nearestPoint(line, to: cd) {
                        PointMark(x: .value("Time", cd), y: .value("Percent", p.percent))
                            .foregroundStyle(line.color)
                            .symbolSize(55)
                    }
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)%").font(Theme.num(10)).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel().font(Theme.num(9.5)).foregroundStyle(Theme.textTertiary)
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotFrame = proxy.plotFrame {
                    let rect = geo[plotFrame]
                    ForEach(series) { line in
                        if showsDot(line), let last = line.points.last,
                           let x = proxy.position(forX: last.date),
                           let y = proxy.position(forY: last.percent) {
                            PulsingDot(color: line.color.opacity(lineOpacity(line)))
                                .position(x: rect.minX + x, y: rect.minY + y)
                        }
                    }
                }
            }
        }
    }

    /// Tooltip listing the date and each visible line's value at the cursor.
    private func crosshairTooltip(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.num(9.5)).foregroundStyle(Theme.textTertiary)
            ForEach(tooltipLines) { line in
                if let p = nearestPoint(line, to: date) {
                    HStack(spacing: 5) {
                        Circle().fill(line.color).frame(width: 6, height: 6)
                        if series.count > 1 {
                            Text(line.label).font(Theme.ui(10.5, .medium))
                                .foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text("\(Int(p.percent.rounded()))%")
                            .font(Theme.num(11, .semibold)).foregroundStyle(Theme.text)
                    }
                }
            }
        }
        .frame(minWidth: series.count > 1 ? 120 : 44)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1)))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private var selector: some View {
        HStack(spacing: 18) {
            Spacer()
            ForEach(DetailStore.Timeframe.allCases, id: \.self) { tf in
                Button {
                    guard tf != timeframe else { return }
                    timeframe = tf
                    onTimeframeChange()
                } label: {
                    Text(tf.rawValue)
                        .font(Theme.ui(13, .medium))
                        .foregroundStyle(tf == timeframe ? Theme.text : Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
