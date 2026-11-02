import SwiftUI
import Charts

struct ChartSeries: Identifiable {
    let id: String
    let title: String
    let unit: String
    let color: Color
    let inverted: Bool             // pace: lower is better, so draw it with a reversed axis
    let points: [ChartPoint]
    let format: (Double) -> String
}

struct ChartPoint: Identifiable { let t: Double; let v: Double; var id: Double { t } }

/// Full-screen, pinch-to-zoom, drag-to-scrub chart.
struct ChartDetailView: View {
    let series: ChartSeries
    @Environment(\.dismiss) private var dismiss

    @State private var visibleSeconds: Double = 0        // zoom level (x-axis window)
    @State private var pinchStart: Double = 0
    @State private var scrollPosition: Double = 0
    @State private var selectedT: Double?

    private var total: Double { series.points.last?.t ?? 0 }
    private var minWindow: Double { 30 }

    private var yDomain: ClosedRange<Double> {
        let vs = series.points.map(\.v)
        guard let lo = vs.min(), let hi = vs.max(), hi > lo else { return 0...1 }
        let pad = (hi - lo) * 0.1
        return (lo - pad)...(hi + pad)
    }

    private var selected: ChartPoint? {
        guard let t = selectedT else { return nil }
        return series.points.min { abs($0.t - t) < abs($1.t - t) }
    }

    /// Stats for the currently visible window.
    private var windowStats: (avg: Double, min: Double, max: Double)? {
        let w = series.points.filter { $0.t >= scrollPosition && $0.t <= scrollPosition + visibleSeconds }
        guard !w.isEmpty else { return nil }
        return (w.map(\.v).reduce(0, +) / Double(w.count), w.map(\.v).min()!, w.map(\.v).max()!)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                readout
                chart
                zoomBar
            }
            .padding()
            .navigationTitle(series.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if visibleSeconds == 0 { visibleSeconds = max(minWindow, total) } }
        }
    }

    private var readout: some View {
        HStack(alignment: .firstTextBaseline) {
            if let p = selected {
                VStack(alignment: .leading) {
                    Text(Fmt.clock(p.t)).font(.caption).foregroundStyle(.secondary)
                    Text(series.format(p.v)).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(series.color).monospacedDigit()
                }
            } else if let s = windowStats {
                VStack(alignment: .leading) {
                    Text("Visible window").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        stat("avg", series.format(s.avg))
                        stat(series.inverted ? "best" : "max", series.format(series.inverted ? s.min : s.max))
                        stat(series.inverted ? "worst" : "min", series.format(series.inverted ? s.max : s.min))
                    }
                }
            }
            Spacer()
            Text(series.unit).font(.caption).foregroundStyle(.secondary)
        }
        .frame(height: 56)
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(k).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.title3.bold()).monospacedDigit()
        }
    }

    private var chart: some View {
        Chart {
            ForEach(series.points) { p in
                LineMark(x: .value("t", p.t), y: .value(series.title, p.v))
                    .foregroundStyle(series.color).interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 2))
                AreaMark(x: .value("t", p.t), yStart: .value("base", series.inverted ? yDomain.upperBound : yDomain.lowerBound), yEnd: .value(series.title, p.v))
                    .foregroundStyle(series.color.opacity(0.12)).interpolationMethod(.monotone)
            }
            if let p = selected {
                RuleMark(x: .value("sel", p.t)).foregroundStyle(.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                PointMark(x: .value("t", p.t), y: .value("v", p.v)).foregroundStyle(series.color).symbolSize(90)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false, reversed: series.inverted))
        .chartXScale(domain: 0...max(total, 1))
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: max(minWindow, visibleSeconds))
        .chartScrollPosition(x: $scrollPosition)
        .chartXSelection(value: $selectedT)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { v in
            AxisGridLine(); AxisValueLabel { if let s = v.as(Double.self) { Text(Fmt.clock(s)) } }
        } }
        .chartYAxis { AxisMarks(position: .trailing) { v in
            AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(series.format(d)) } }
        } }
        .gesture(
            MagnifyGesture()
                .onChanged { g in
                    if pinchStart == 0 { pinchStart = visibleSeconds }
                    visibleSeconds = min(max(minWindow, pinchStart / g.magnification), max(minWindow, total))
                }
                .onEnded { _ in pinchStart = 0 }
        )
        .frame(maxHeight: .infinity)
    }

    private var zoomBar: some View {
        HStack {
            Button { zoom(by: 2) } label: { Image(systemName: "minus.magnifyingglass") }
            Slider(value: Binding(get: { log(visibleSeconds) }, set: { visibleSeconds = exp($0) }),
                   in: log(minWindow)...log(max(minWindow + 1, total)))
            Button { zoom(by: 0.5) } label: { Image(systemName: "plus.magnifyingglass") }
            Button("All") { visibleSeconds = max(minWindow, total); scrollPosition = 0 }.buttonStyle(.bordered).controlSize(.small)
        }
    }

    private func zoom(by f: Double) {
        let centre = scrollPosition + visibleSeconds / 2
        visibleSeconds = min(max(minWindow, visibleSeconds * f), max(minWindow, total))
        scrollPosition = max(0, centre - visibleSeconds / 2)
    }
}
