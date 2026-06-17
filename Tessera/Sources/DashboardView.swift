import SwiftUI

/// The full-window market browser: header, category filter, and a scrollable
/// grid of event cards over Tessera's dark terminal background.
struct DashboardView: View {
    var store: WatchlistStore
    @State private var category: String = "All"
    @State private var appeared = false

    private var filtered: [EventVM] {
        category == "All" ? store.events : store.events.filter { $0.category == category }
    }

    private let columns = [GridItem(.adaptive(minimum: 320, maximum: 480), spacing: 12)]

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                header
                categoryBar
                Divider().overlay(Theme.stroke)
                content
            }
        }
        .frame(minWidth: 660, minHeight: 540)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }

    // MARK: Backdrop — subtle mint glow for atmosphere, not a flat fill.
    private var backdrop: some View {
        ZStack {
            Theme.bg
            RadialGradient(
                colors: [Theme.mint.opacity(0.08), .clear],
                center: .topLeading, startRadius: 10, endRadius: 600
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .center) {
            Wordmark()
            Text("for Kalshi")
                .font(Theme.body(11)).foregroundStyle(Theme.textTertiary)
                .padding(.leading, -2).padding(.top, 4)
            Spacer()
            LiveDot()
            Text("\(store.events.count) markets")
                .font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
            if let updated = store.lastUpdated {
                Text("· \(updated.formatted(date: .omitted, time: .standard))")
                    .font(Theme.mono(11)).foregroundStyle(Theme.textTertiary)
            }
            Button { Task { await store.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .rotationEffect(.degrees(store.isLoading ? 360 : 0))
                    .animation(store.isLoading ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                               value: store.isLoading)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.categories, id: \.self) { cat in
                    FilterChip(title: cat, selected: cat == category) {
                        withAnimation(.easeOut(duration: 0.2)) { category = cat }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 12)
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.errorMessage, store.events.isEmpty {
            emptyState(icon: "exclamationmark.triangle", title: "Couldn’t load markets", subtitle: error)
        } else if store.events.isEmpty {
            emptyState(icon: "chart.line.uptrend.xyaxis", title: "Loading markets…", subtitle: "Fetching live odds from Kalshi")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, event in
                        EventCardView(event: event)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)
                            .animation(.easeOut(duration: 0.4).delay(Double(min(index, 12)) * 0.03), value: appeared)
                    }
                }
                .padding(18)
            }
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(Theme.textTertiary)
            Text(title).font(Theme.display(16, .semibold)).foregroundStyle(Theme.text)
            Text(subtitle).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
