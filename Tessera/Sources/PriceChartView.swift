import SwiftUI
import Charts
import KalshiKit

/// Implied-probability line chart with hover scrubbing and a Kalshi-style
/// text-only timeframe selector beneath it.
struct PriceChartView: View {
    let candles: [Candlestick]
    let isLoading: Bool
    @Binding var timeframe: DetailStore.Timeframe
    var onTimeframeChange: () -> Void = {}

    /// One charted sample: time × implied percent (0…100).
    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let percent: Double
    }

    @State private var selectedDate: Date?

    private var points: [Point] {
        candles.compactMap { candle in
            guard let date = candle.endPeriodDate, let prob = candle.probability else { return nil }
            return Point(date: date, percent: NSDecimalNumber(decimal: prob * 100).doubleValue)
        }
    }

    /// Green when the window closed up (or flat), red when down.
    private var lineColor: Color {
        guard let first = points.first?.percent, let last = points.last?.percent else { return Theme.yes }
        return last >= first ? Theme.yes : Theme.no
    }

    /// The point nearest the hovered date, for the crosshair annotation.
    private var selectedPoint: Point? {
        guard let selectedDate else { return nil }
        return points.min(by: {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        })
    }

    var body: some View {
        VStack(spacing: 12) {
            chartArea
                .frame(height: 240)
            selector
        }
    }

    @ViewBuilder
    private var chartArea: some View {
        if points.count >= 2 {
            chart
        } else if isLoading {
            placeholder { ProgressView().controlSize(.small) }
        } else {
            placeholder {
                Text("No price history")
                    .font(Theme.ui(13, .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func placeholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chart: some View {
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("Time", p.date), y: .value("Percent", p.percent))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                AreaMark(x: .value("Time", p.date), y: .value("Percent", p.percent))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        .linearGradient(
                            colors: [lineColor.opacity(0.16), lineColor.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }

            if let sp = selectedPoint {
                RuleMark(x: .value("Time", sp.date))
                    .foregroundStyle(Theme.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        crosshairLabel(sp)
                    }

                PointMark(x: .value("Time", sp.date), y: .value("Percent", sp.percent))
                    .foregroundStyle(lineColor)
                    .symbolSize(60)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)%")
                            .font(Theme.num(10, .regular))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .chartXSelection(value: $selectedDate)
    }

    private func crosshairLabel(_ p: Point) -> some View {
        VStack(spacing: 1) {
            Text("\(Int(p.percent.rounded()))%")
                .font(Theme.num(13, .semibold))
                .foregroundStyle(Theme.text)
            Text(p.date.formatted(date: .omitted, time: .shortened))
                .font(Theme.num(9.5, .regular))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        )
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
