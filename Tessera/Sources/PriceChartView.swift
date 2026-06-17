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

    private typealias Point = DetailStore.ChartPoint
    @State private var selectedDate: Date?

    private var isMulti: Bool { series.count > 1 }
    private var hasData: Bool { series.contains { $0.points.count >= 2 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isMulti { legend }
            chartArea.frame(height: 240)
            selector
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(series) { line in
                HStack(spacing: 6) {
                    Circle().fill(line.color).frame(width: 8, height: 8)
                    Text(line.label).font(Theme.ui(12, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    if let p = line.lastPercent {
                        Text("\(Int(p.rounded()))%").font(Theme.num(12, .semibold)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
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

    private var singleLineColor: Color {
        guard let pts = series.first?.points, let first = pts.first?.percent, let last = pts.last?.percent
        else { return Theme.yes }
        return series.first?.color ?? (last >= first ? Theme.yes : Theme.no)
    }

    private var selectedPoint: Point? {
        guard !isMulti, let selectedDate, let pts = series.first?.points else { return nil }
        return pts.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
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
                    .foregroundStyle(line.color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                if !isMulti {
                    ForEach(line.points) { p in
                        AreaMark(x: .value("Time", p.date), y: .value("Percent", p.percent))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(.linearGradient(
                                colors: [line.color.opacity(0.16), line.color.opacity(0)],
                                startPoint: .top, endPoint: .bottom))
                    }
                }

                if let last = line.points.last {
                    PointMark(x: .value("Time", last.date), y: .value("Percent", last.percent))
                        .foregroundStyle(line.color)
                        .symbolSize(55)
                }
            }

            if let sp = selectedPoint {
                RuleMark(x: .value("Time", sp.date))
                    .foregroundStyle(Theme.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        crosshairLabel(sp)
                    }
                PointMark(x: .value("Time", sp.date), y: .value("Percent", sp.percent))
                    .foregroundStyle(singleLineColor).symbolSize(60)
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
        .chartXSelection(value: isMulti ? .constant(nil) : $selectedDate)
    }

    private func crosshairLabel(_ p: Point) -> some View {
        VStack(spacing: 1) {
            Text("\(Int(p.percent.rounded()))%").font(Theme.num(13, .semibold)).foregroundStyle(Theme.text)
            Text(p.date.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.num(9.5)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1)))
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
