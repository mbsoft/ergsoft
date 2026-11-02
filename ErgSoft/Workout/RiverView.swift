import SwiftUI

/// First-person rowing scene: a perspective river scrolling at the athlete's real speed,
/// bank-side distance markers, and oars that swing with the live stroke rate.
struct RiverView: View {
    @EnvironmentObject var engine: WorkoutEngine
    @EnvironmentObject var settings: UserSettings
    @StateObject private var sim = RiverSim()

    var body: some View {
        ZStack {
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    sim.advance(to: tl.date, engine: engine)
                    RiverPainter(size: size, meters: sim.meters, strokePhase: sim.strokePhase,
                                 strokeRate: engine.current.strokeRate ?? 0, units: settings.units).draw(&ctx)
                }
            }
            .ignoresSafeArea()
            VStack {
                hud
                Spacer()
                intervalStrip
            }
        }
    }

    private var hud: some View {
        let c = engine.current
        return HStack(spacing: 18) {
            hudItem(L10n.t("time"), Fmt.clock(engine.elapsed))
            hudItem(settings.units == .metric ? L10n.t("meters") : L10n.t("distance"),
                    settings.units == .metric ? Fmt.meters(engine.meters) : settings.distance(engine.meters))
            hudItem(L10n.t("pace"), Fmt.pace(c.paceSecondsPer500m))
            hudItem(L10n.t("watts"), c.powerWatts.map(String.init) ?? "--")
            hudItem("s/m", c.strokeRate.map { String(Int($0.rounded())) } ?? "--")
            hudItem(L10n.t("heart"), engine.heartRate.map(String.init) ?? "--",
                    tint: engine.heartRate.map { HRZone.color(settings.zone(for: $0)) } ?? .white)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.black.opacity(0.35), in: Capsule())
        .padding(.top, 12)
    }

    private func hudItem(_ label: String, _ value: String, tint: Color = .white) -> some View {
        VStack(spacing: 0) {
            Text(label.uppercased()).font(.caption2.bold()).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
        }
    }

    @ViewBuilder private var intervalStrip: some View {
        if let iv = engine.currentInterval {
            VStack(spacing: 4) {
                Text("\(engine.intervalIndex + 1)/\(engine.plan.intervals.count)  \(iv.label)  ·  \(engine.intervalRemainingText)")
                    .font(.headline).foregroundStyle(.white)
                ProgressView(value: engine.intervalProgress ?? 0).tint(iv.kind == .rest ? .blue : .orange).frame(width: 320)
            }
            .padding(12).background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 16)
        }
    }
}

/// Smooths distance between BLE packets and tracks oar phase.
@MainActor
final class RiverSim: ObservableObject {
    private(set) var meters: Double = 0
    private(set) var strokePhase: Double = 0     // 0…1, one full stroke
    private var last: Date?
    private var velocity: Double = 0             // m/s

    func advance(to now: Date, engine: WorkoutEngine) {
        defer { last = now }
        guard let last else { meters = engine.meters; return }
        let dt = min(0.1, now.timeIntervalSince(last))
        let target = engine.meters
        // velocity from pace when available, else infer from distance error
        if engine.state == .running, let p = engine.current.paceSecondsPer500m, p > 0 { velocity = 500 / p }
        else if engine.state != .running { velocity = 0 }
        meters += velocity * dt
        // pull toward the machine's reported distance so we never drift
        meters += (target - meters) * min(1, dt * 1.5)
        if engine.state == .running, let sr = engine.current.strokeRate, sr > 0 {
            strokePhase = (strokePhase + dt * sr / 60).truncatingRemainder(dividingBy: 1)
        }
    }
}

struct RiverPainter {
    let size: CGSize
    let meters: Double
    let strokePhase: Double
    let strokeRate: Double
    let units: UnitSystem

    private var horizonY: CGFloat { size.height * 0.42 }
    private let viewDistance: Double = 400         // metres visible ahead
    private let markerEvery: Double = 100

    /// Perspective: distance ahead (m) → screen y and scale (1 = at the bow).
    private func project(_ d: Double) -> (y: CGFloat, s: CGFloat) {
        let near = 6.0
        let t = near / (near + max(0, d))           // 1 at bow → 0 at infinity
        return (horizonY + (size.height - horizonY) * CGFloat(t), CGFloat(t))
    }
    private func riverHalfWidth(at y: CGFloat) -> CGFloat {
        let t = (y - horizonY) / (size.height - horizonY)
        return size.width * (0.02 + 0.46 * t)
    }

    func draw(_ ctx: inout GraphicsContext) {
        drawSky(&ctx); drawBanks(&ctx); drawWater(&ctx); drawMarkers(&ctx); drawBoat(&ctx)
    }

    private func drawSky(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: horizonY)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.45, green: 0.70, blue: 0.95), Color(red: 0.80, green: 0.90, blue: 0.98)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: horizonY)))
        // distant hills
        var hills = Path(); hills.move(to: CGPoint(x: 0, y: horizonY))
        for i in 0...12 {
            let x = size.width * CGFloat(i) / 12
            let h = 14 + 22 * abs(sin(Double(i) * 1.7 + 0.4))
            hills.addQuadCurve(to: CGPoint(x: x, y: horizonY - CGFloat(h)), control: CGPoint(x: x - size.width / 24, y: horizonY - CGFloat(h) - 10))
        }
        hills.addLine(to: CGPoint(x: size.width, y: horizonY)); hills.closeSubpath()
        ctx.fill(hills, with: .color(Color(red: 0.45, green: 0.62, blue: 0.50)))
    }

    private func drawBanks(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(CGRect(x: 0, y: horizonY, width: size.width, height: size.height - horizonY)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.42, green: 0.60, blue: 0.32), Color(red: 0.28, green: 0.48, blue: 0.22)]),
                                       startPoint: CGPoint(x: 0, y: horizonY), endPoint: CGPoint(x: 0, y: size.height)))
        // trees along both banks, spaced every 25 m in world space
        let spacing = 25.0
        let first = floor(meters / spacing) * spacing
        var d = first - meters
        while d < viewDistance {
            if d > 0 {
                let (y, s) = project(d)
                let hw = riverHalfWidth(at: y)
                let seed = (first + (d + meters - first)).truncatingRemainder(dividingBy: 1000)
                let jitter = CGFloat(12 + 40 * abs(sin(seed * 0.37)))
                for side in [-1.0, 1.0] {
                    let x = size.width / 2 + CGFloat(side) * (hw + jitter + 30 * s)
                    tree(&ctx, at: CGPoint(x: x, y: y), scale: s, seed: seed * side)
                }
            }
            d += spacing
        }
    }

    private func tree(_ ctx: inout GraphicsContext, at p: CGPoint, scale s: CGFloat, seed: Double) {
        let h = 90 * s + 2, w = 40 * s + 1
        let trunk = Path(CGRect(x: p.x - w * 0.08, y: p.y - h * 0.3, width: w * 0.16, height: h * 0.3))
        ctx.fill(trunk, with: .color(Color(red: 0.35, green: 0.25, blue: 0.15)))
        let g = 0.30 + 0.15 * abs(sin(seed))
        var crown = Path()
        crown.addEllipse(in: CGRect(x: p.x - w / 2, y: p.y - h, width: w, height: h * 0.75))
        ctx.fill(crown, with: .color(Color(red: 0.12, green: g, blue: 0.12)))
    }

    private func drawWater(_ ctx: inout GraphicsContext) {
        var river = Path()
        river.move(to: CGPoint(x: size.width / 2 - riverHalfWidth(at: horizonY), y: horizonY))
        river.addLine(to: CGPoint(x: size.width / 2 + riverHalfWidth(at: horizonY), y: horizonY))
        river.addLine(to: CGPoint(x: size.width / 2 + riverHalfWidth(at: size.height), y: size.height))
        river.addLine(to: CGPoint(x: size.width / 2 - riverHalfWidth(at: size.height), y: size.height))
        river.closeSubpath()
        ctx.fill(river, with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.72, blue: 0.85), Color(red: 0.16, green: 0.40, blue: 0.62)]),
                                              startPoint: CGPoint(x: 0, y: horizonY), endPoint: CGPoint(x: 0, y: size.height)))
        // ripples: world-anchored lines every 4 m so they stream toward the viewer at real speed
        let spacing = 4.0
        var d = (spacing - meters.truncatingRemainder(dividingBy: spacing))
        var ripples = Path()
        while d < viewDistance {
            let (y, s) = project(d)
            let hw = riverHalfWidth(at: y)
            let phase = sin((d + meters) * 0.9)
            let inset = hw * (0.15 + 0.5 * abs(phase))
            let x0 = size.width / 2 - hw + inset, x1 = size.width / 2 + hw - inset * 0.6
            ripples.move(to: CGPoint(x: x0, y: y)); ripples.addLine(to: CGPoint(x: x1, y: y))
            d += spacing * (1 + 0.5 * Double(1 - s))
        }
        ctx.stroke(ripples, with: .color(.white.opacity(0.18)), lineWidth: 1)
    }

    private func drawMarkers(_ ctx: inout GraphicsContext) {
        let first = (floor(meters / markerEvery) + 1) * markerEvery
        var m = first
        while m - meters < viewDistance {
            let d = m - meters
            let (y, s) = project(d)
            let hw = riverHalfWidth(at: y)
            let major = m.truncatingRemainder(dividingBy: 500) == 0
            let x = size.width / 2 - hw - 14 * s - 6
            let h = (major ? 120 : 70) * s + 3
            // post
            ctx.fill(Path(CGRect(x: x - 3 * s - 1, y: y - h, width: 6 * s + 2, height: h)), with: .color(major ? .orange : .white))
            // label plate
            if s > 0.08 {
                let label = units == .imperial && major ? String(format: "%.2f mi", m / 1609.344) : "\(Int(m))"
                let font = Font.system(size: (major ? 34 : 22) * s + 6, weight: .heavy, design: .rounded)
                let text = ctx.resolve(Text(label).font(font).foregroundStyle(.white))
                let ts = text.measure(in: CGSize(width: 400, height: 200))
                let plate = CGRect(x: x - ts.width / 2 - 6 * s, y: y - h - ts.height - 6 * s, width: ts.width + 12 * s, height: ts.height + 6 * s)
                ctx.fill(Path(roundedRect: plate, cornerRadius: 4), with: .color(major ? .orange : Color(red: 0.1, green: 0.3, blue: 0.5)))
                ctx.draw(text, at: CGPoint(x: plate.midX, y: plate.midY), anchor: .center)
            }
            m += markerEvery
        }
    }

    private func drawBoat(_ ctx: inout GraphicsContext) {
        // bow (deck seen from the rower's seat) at the bottom centre
        let cx = size.width / 2, by = size.height
        var bow = Path()
        bow.move(to: CGPoint(x: cx - 70, y: by))
        bow.addQuadCurve(to: CGPoint(x: cx, y: by - 150), control: CGPoint(x: cx - 40, y: by - 90))
        bow.addQuadCurve(to: CGPoint(x: cx + 70, y: by), control: CGPoint(x: cx + 40, y: by - 90))
        bow.closeSubpath()
        ctx.fill(bow, with: .linearGradient(Gradient(colors: [Color(red: 0.95, green: 0.93, blue: 0.85), Color(red: 0.75, green: 0.72, blue: 0.62)]),
                                            startPoint: CGPoint(x: cx, y: by - 150), endPoint: CGPoint(x: cx, y: by)))
        ctx.stroke(bow, with: .color(.black.opacity(0.3)), lineWidth: 2)

        // oars: angle sweeps with stroke phase; catch at phase 0 (oars forward), finish at ~0.35
        let drive = strokePhase < 0.35 ? strokePhase / 0.35 : 1 - (strokePhase - 0.35) / 0.65
        // Oar angle from straight-ahead: catch ≈ 35° toward the bow, finish ≈ 35° toward the stern.
        // Computed once for the right-hand oar and mirrored in x for the left, so they sweep symmetrically.
        let ang = CGFloat(0.6 - 1.2 * drive)            // radians; + = toward bow, − = toward stern
        let len: CGFloat = 320
        for side: CGFloat in [-1, 1] {
            let pivot = CGPoint(x: cx + side * 90, y: by - 40)
            let outward = len * cos(ang) * 0.75            // sideways reach
            let forward = len * sin(ang) * 0.55            // toward the horizon (+) or the viewer (−)
            let tip = CGPoint(x: pivot.x + side * outward, y: pivot.y - 110 - forward)
            var oar = Path(); oar.move(to: pivot); oar.addLine(to: tip)
            ctx.stroke(oar, with: .color(Color(red: 0.9, green: 0.85, blue: 0.6)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            // blade
            let blade = CGRect(x: tip.x - 14, y: tip.y - 8, width: 28, height: 16)
            ctx.fill(Path(ellipseIn: blade), with: .color(strokeRate > 0 && drive > 0.05 && drive < 0.95 ? .red : Color(red: 0.8, green: 0.1, blue: 0.1)))
            // splash on the drive
            if strokeRate > 0, drive > 0.1, drive < 0.9, strokePhase < 0.35 {
                var sp = Path()
                for i in 0..<5 {
                    let a = Double(i) * 0.6 - 1.2
                    sp.move(to: tip); sp.addLine(to: CGPoint(x: tip.x + CGFloat(cos(a)) * 18, y: tip.y - CGFloat(sin(a) + 1) * 12))
                }
                ctx.stroke(sp, with: .color(.white.opacity(0.7)), lineWidth: 2)
            }
        }
    }
}
