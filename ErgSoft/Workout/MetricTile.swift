import SwiftUI

struct MetricTile: View {
    let label: String
    let value: String
    var unit: String = ""
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(tint).minimumScaleFactor(0.5).lineLimit(1)
            if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}
