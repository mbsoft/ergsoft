import SwiftUI

struct MetricTile: View {
    let label: String
    let value: String
    var unit: String = ""
    var tint: Color = .primary
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 0 : 2) {
            Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: compact ? 28 : 36, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(tint).minimumScaleFactor(0.5).lineLimit(1)
            if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, maxHeight: compact ? .infinity : nil)
        .padding(.vertical, compact ? 4 : 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}
