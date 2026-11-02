import WidgetKit
import SwiftUI

/// Static launcher complication: tap to open ErgSoft on the watch.
struct LaunchEntry: TimelineEntry { let date: Date }

struct LaunchProvider: TimelineProvider {
    func placeholder(in context: Context) -> LaunchEntry { LaunchEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (LaunchEntry) -> Void) { completion(LaunchEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LaunchEntry>) -> Void) {
        completion(Timeline(entries: [LaunchEntry(date: .now)], policy: .never))
    }
}

struct LaunchView: View {
    @Environment(\.widgetFamily) private var family
    var entry: LaunchEntry

    var body: some View {
        switch family {
        case .accessoryCorner:
            RowerGlyph(size: 26)
                .widgetLabel { Text("ErgSoft") }
        case .accessoryInline:
            Label { Text("ErgSoft") } icon: { RowerGlyph(size: 14) }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                RowerGlyph(size: 30)
                VStack(alignment: .leading) {
                    Text("ErgSoft").font(.headline)
                    Text("Start HR stream").font(.caption2).foregroundStyle(.secondary)
                }
            }
        default: // .accessoryCircular
            ZStack {
                AccessoryWidgetBackground()
                RowerGlyph(size: 28)
            }
        }
    }
}

@main
struct ErgSoftWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ErgSoftLaunch", provider: LaunchProvider()) { entry in
            LaunchView(entry: entry).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("ErgSoft")
        .description("Open ErgSoft to stream heart rate to your erg.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}
