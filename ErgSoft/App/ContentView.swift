import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case workout, stats, history, devices, settings
    var id: String { rawValue }
    var title: String { L10n.t(rawValue) }
    var icon: String {
        switch self {
        case .workout: "figure.rower"; case .stats: "chart.bar.xaxis"; case .history: "clock.arrow.circlepath"
        case .devices: "antenna.radiowaves.left.and.right"; case .settings: "gearshape"
        }
    }
}

/// Drawer state shared with every screen so a toolbar button can open it.
@MainActor
final class AppNav: ObservableObject {
    @Published var screen: Screen = .workout
    @Published var drawerOpen = false
    func toggle() { withAnimation(.spring(duration: 0.3)) { drawerOpen.toggle() } }
    func go(_ s: Screen) { screen = s; withAnimation(.spring(duration: 0.3)) { drawerOpen = false } }
}

/// Full-screen content with a slide-out navigation drawer instead of a tab bar.
struct ContentView: View {
    @EnvironmentObject var engine: WorkoutEngine
    @EnvironmentObject var settings: UserSettings
    @EnvironmentObject var ble: BLEManager
    @StateObject private var nav = AppNav()
    @GestureState private var dragX: CGFloat = 0

    private let drawerWidth: CGFloat = 280

    var body: some View {
        ZStack(alignment: .leading) {
            content
                .environmentObject(nav)
                .disabled(nav.drawerOpen)

            if nav.drawerOpen {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { nav.toggle() }
                    .transition(.opacity)
            }

            drawer
                .frame(width: drawerWidth)
                .offset(x: (nav.drawerOpen ? 0 : -drawerWidth) + dragX)
        }
        .gesture(edgeSwipe)
        .preferredColorScheme(settings.appearance.scheme)
        .onChange(of: engine.state) { _, s in if s == .running { nav.go(.workout) } }
        .id(settings.languageRaw)
    }

    @ViewBuilder private var content: some View {
        switch nav.screen {
        case .workout: WorkoutView()
        case .stats: StatsView()
        case .history: HistoryView()
        case .devices: DevicesView()
        case .settings: SettingsView()
        }
    }

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                RowerGlyph(size: 30)
                Text("ErgSoft").font(.title2.bold())
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 24)

            ForEach(Screen.allCases) { s in
                Button { nav.go(s) } label: {
                    HStack(spacing: 14) {
                        if s == .workout { RowerGlyph(size: 22).frame(width: 26) } else { Image(systemName: s.icon).frame(width: 26) }
                        Text(s.title).font(.title3)
                        Spacer()
                        if s == .workout && (engine.state == .running || engine.state == .paused) {
                            Circle().fill(engine.state == .running ? .green : .orange).frame(width: 8, height: 8)
                        }
                    }
                    .foregroundStyle(nav.screen == s ? Color.accentColor : .primary)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(nav.screen == s ? Color.accentColor.opacity(0.12) : .clear)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(ble.ergConnected ? .green : .gray).frame(width: 8, height: 8)
                    Text(ble.ergConnected ? ble.ergName : L10n.t("no_machine")).font(.caption)
                }
                if engine.state == .running || engine.state == .paused {
                    Text("\(Fmt.clock(engine.elapsed)) · \(settings.distance(engine.meters, compact: false))").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                Text("ErgSoft \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · GPL-3.0").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(20)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        .ignoresSafeArea()
    }

    /// Swipe right from the left edge opens; swipe left anywhere on the open drawer closes.
    private var edgeSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .updating($dragX) { v, st, _ in
                if nav.drawerOpen { st = min(0, v.translation.width) }
                else if v.startLocation.x < 30 { st = min(drawerWidth, max(0, v.translation.width)) }
            }
            .onEnded { v in
                if nav.drawerOpen, v.translation.width < -60 { nav.toggle() }
                else if !nav.drawerOpen, v.startLocation.x < 30, v.translation.width > 60 { nav.toggle() }
            }
    }
}

/// ☰ button for a screen's toolbar.
struct MenuButton: View {
    @EnvironmentObject var nav: AppNav
    var body: some View {
        Button { nav.toggle() } label: { Image(systemName: "line.3.horizontal") }
            .accessibilityLabel("Menu")
    }
}

/// Floating ☰ for screens that hide their navigation bar.
struct FloatingMenuButton: View {
    @EnvironmentObject var nav: AppNav
    var body: some View {
        Button { nav.toggle() } label: {
            Image(systemName: "line.3.horizontal").font(.title3.bold()).foregroundStyle(.white)
                .padding(10).background(.black.opacity(0.35), in: Circle())
        }
        .padding(.leading, 12).padding(.top, 8)
    }
}
