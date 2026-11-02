import Foundation
import CoreBluetooth

/// Bluetooth SIG Fitness Machine Service UUIDs and decoders.
enum FTMS {
    static let service            = CBUUID(string: "1826")
    static let feature            = CBUUID(string: "2ACC")
    static let rowerData          = CBUUID(string: "2AD1")
    static let indoorBikeData     = CBUUID(string: "2AD2")
    static let crossTrainerData   = CBUUID(string: "2ACE")
    static let trainingStatus     = CBUUID(string: "2AD3")
    static let controlPoint       = CBUUID(string: "2AD9")
    static let machineStatus      = CBUUID(string: "2ADA")
    static let supportedPowerRange      = CBUUID(string: "2AD8")
    static let supportedResistanceRange = CBUUID(string: "2AD6")
    static let supportedHRRange         = CBUUID(string: "2AD7")

    /// Fitness Machine Feature (0x2ACC): two 32-bit bitmasks.
    struct Feature {
        let machine: UInt32, target: UInt32
        static let machineNames = ["Avg speed","Cadence","Total distance","Inclination","Elevation gain","Pace","Step count","Resistance level","Stride count","Expended energy","Heart rate","MET","Elapsed time","Remaining time","Power measurement","Force on belt & power output","User data retention"]
        static let targetNames  = ["Speed target","Inclination target","Resistance target","Power target","HR target","Expended energy cfg","Step number cfg","Stride number cfg","Distance cfg","Training time cfg","Time in 2 HR zones","Time in 3 HR zones","Time in 5 HR zones","Indoor bike simulation","Wheel circumference","Spin down control","Cadence cfg"]
        var machineList: [String] { Feature.machineNames.enumerated().filter { machine & (1 << UInt32($0.offset)) != 0 }.map(\.element) }
        var targetList:  [String] { Feature.targetNames.enumerated().filter  { target  & (1 << UInt32($0.offset)) != 0 }.map(\.element) }
        init?(_ d: Data) { var r = ByteReader(d); guard let a = r.u32(), let b = r.u32() else { return nil }; machine = a; target = b }
    }

    static func trainingStatusText(_ d: Data) -> String {
        var r = ByteReader(d); _ = r.u8()
        switch r.u8() ?? 0xFF {
        case 0x00: return "Other"; case 0x01: return "Idle"; case 0x02: return "Warming up"; case 0x03: return "Low intensity interval"
        case 0x04: return "High intensity interval"; case 0x05: return "Recovery interval"; case 0x06: return "Isometric"; case 0x07: return "HR control"
        case 0x08: return "Fitness test"; case 0x09: return "Speed outside control region (low)"; case 0x0A: return "Speed outside control region (high)"
        case 0x0B: return "Cool down"; case 0x0C: return "Watt control"; case 0x0D: return "Manual mode"; case 0x0E: return "Pre-workout"; case 0x0F: return "Post-workout"
        case let x: return String(format: "0x%02X", x)
        }
    }

    static func machineStatusText(_ d: Data) -> String {
        var r = ByteReader(d)
        switch r.u8() ?? 0xFF {
        case 0x01: return "Reset"
        case 0x02: return "Stopped/paused by user" + ((r.u8() == 0x02) ? " (pause)" : " (stop)")
        case 0x03: return "Stopped by safety key"
        case 0x04: return "Started/resumed by user"
        case 0x05: return "Target speed changed"; case 0x06: return "Target incline changed"; case 0x07: return "Target resistance changed"
        case 0x08: return "Target power changed \(r.s16() ?? 0) W"; case 0x09: return "Target HR changed \(r.u8() ?? 0)"
        case 0x0A: return "Target energy changed"; case 0x0C: return "Target distance changed \(r.u24() ?? 0) m"
        case 0x0D: return "Target time changed \(r.u16() ?? 0) s"
        case 0xFF: return "Control permission lost"
        case let x: return String(format: "Status 0x%02X", x)
        }
    }

    // Control point opcodes
    enum Op: UInt8 {
        case requestControl = 0x00
        case reset          = 0x01
        case startOrResume  = 0x07
        case stopOrPause    = 0x08
    }
}

enum HRS {
    static let service     = CBUUID(string: "180D")
    static let measurement = CBUUID(string: "2A37")
}

/// Little-endian byte reader that returns nil past the end instead of trapping.
struct ByteReader {
    let data: Data
    var offset = 0
    init(_ d: Data) { data = d }

    mutating func u8()  -> UInt8?  { guard offset + 1 <= data.count else { return nil }; defer { offset += 1 }; return data[data.startIndex + offset] }
    mutating func u16() -> UInt16? { guard let a = u8(), let b = u8() else { return nil }; return UInt16(a) | UInt16(b) << 8 }
    mutating func s16() -> Int16?  { guard let v = u16() else { return nil }; return Int16(bitPattern: v) }
    mutating func u32() -> UInt32? { guard let a = u16(), let b = u16() else { return nil }; return UInt32(a) | UInt32(b) << 16 }
    mutating func u24() -> UInt32? { guard let a = u8(), let b = u8(), let c = u8() else { return nil }; return UInt32(a) | UInt32(b) << 8 | UInt32(c) << 16 }
}

/// A snapshot of what the machine reported in one notification. All optional:
/// FTMS packets only carry the fields their flag bits enable.
struct ErgSample: Equatable {
    var strokeRate: Double?        // strokes/min (rower) or cadence rpm (bike)
    var strokeCount: Int?
    var distanceMeters: Double?
    var paceSecondsPer500m: Double?   // rower only
    var speedKph: Double?             // bike only
    var powerWatts: Int?
    var averagePowerWatts: Int?
    var resistanceLevel: Int?
    var caloriesTotal: Int?
    var caloriesPerHour: Int?
    var heartRate: Int?
    var elapsedSeconds: Int?
    var remainingSeconds: Int?
    var averageStrokeRate: Double?
    var averagePaceSecondsPer500m: Double?
    var averageSpeedKph: Double?
    var caloriesPerMinute: Int?
    var met: Double?
    var flags: UInt16 = 0
    var raw: Data = Data()

    /// Rower Data characteristic (0x2AD1), FTMS 4.9.
    static func fromRowerData(_ d: Data) -> ErgSample? {
        var r = ByteReader(d)
        guard let flags = r.u16() else { return nil }
        var s = ErgSample(); s.flags = flags; s.raw = d
        let moreData = flags & (1 << 0) != 0
        if !moreData {
            if let sr = r.u8() { s.strokeRate = Double(sr) / 2.0 }
            if let sc = r.u16() { s.strokeCount = Int(sc) }
        }
        if flags & (1 << 1) != 0, let a = r.u8() { s.averageStrokeRate = Double(a) / 2.0 }
        if flags & (1 << 2) != 0, let m = r.u24() { s.distanceMeters = Double(m) }
        if flags & (1 << 3) != 0, let p = r.u16() { s.paceSecondsPer500m = p == 0xFFFF ? nil : Double(p) }
        if flags & (1 << 4) != 0, let p = r.u16() { s.averagePaceSecondsPer500m = p == 0xFFFF ? nil : Double(p) }
        if flags & (1 << 5) != 0, let w = r.s16() { s.powerWatts = Int(w) }
        if flags & (1 << 6) != 0, let w = r.s16() { s.averagePowerWatts = Int(w) }
        if flags & (1 << 7) != 0, let l = r.s16() { s.resistanceLevel = Int(l) }
        if flags & (1 << 8) != 0 {
            if let t = r.u16() { s.caloriesTotal = t == 0xFFFF ? nil : Int(t) }
            if let h = r.u16() { s.caloriesPerHour = h == 0xFFFF ? nil : Int(h) }
            if let m = r.u8() { s.caloriesPerMinute = m == 0xFF ? nil : Int(m) }
        }
        if flags & (1 << 9) != 0, let hr = r.u8(), hr > 0 { s.heartRate = Int(hr) }
        if flags & (1 << 10) != 0, let m = r.u8() { s.met = Double(m) / 10.0 }
        if flags & (1 << 11) != 0, let t = r.u16() { s.elapsedSeconds = Int(t) }
        if flags & (1 << 12) != 0, let t = r.u16() { s.remainingSeconds = Int(t) }
        return s
    }

    /// Indoor Bike Data characteristic (0x2AD2), FTMS 4.9.
    static func fromIndoorBikeData(_ d: Data) -> ErgSample? {
        var r = ByteReader(d)
        guard let flags = r.u16() else { return nil }
        var s = ErgSample(); s.flags = flags; s.raw = d
        let moreData = flags & (1 << 0) != 0
        if !moreData, let v = r.u16() { s.speedKph = Double(v) / 100.0 }
        if flags & (1 << 1) != 0, let v = r.u16() { s.averageSpeedKph = Double(v) / 100.0 }
        if flags & (1 << 2) != 0, let c = r.u16() { s.strokeRate = Double(c) / 2.0 }   // cadence rpm
        if flags & (1 << 3) != 0, let c = r.u16() { s.averageStrokeRate = Double(c) / 2.0 }
        if flags & (1 << 4) != 0, let m = r.u24() { s.distanceMeters = Double(m) }
        if flags & (1 << 5) != 0, let l = r.s16() { s.resistanceLevel = Int(l) }
        if flags & (1 << 6) != 0, let w = r.s16() { s.powerWatts = Int(w) }
        if flags & (1 << 7) != 0, let w = r.s16() { s.averagePowerWatts = Int(w) }
        if flags & (1 << 8) != 0 {
            if let t = r.u16() { s.caloriesTotal = t == 0xFFFF ? nil : Int(t) }
            if let h = r.u16() { s.caloriesPerHour = h == 0xFFFF ? nil : Int(h) }
            if let m = r.u8() { s.caloriesPerMinute = m == 0xFF ? nil : Int(m) }
        }
        if flags & (1 << 9) != 0, let hr = r.u8(), hr > 0 { s.heartRate = Int(hr) }
        if flags & (1 << 10) != 0, let m = r.u8() { s.met = Double(m) / 10.0 }
        if flags & (1 << 11) != 0, let t = r.u16() { s.elapsedSeconds = Int(t) }
        if flags & (1 << 12) != 0, let t = r.u16() { s.remainingSeconds = Int(t) }
        return s
    }

    /// Heart Rate Measurement (0x2A37).
    static func heartRate(from d: Data) -> Int? {
        var r = ByteReader(d)
        guard let flags = r.u8() else { return nil }
        if flags & 0x01 != 0 { return r.u16().map(Int.init) }
        return r.u8().map(Int.init)
    }
}

enum ErgKind: String, Codable { case rower, bike, unknown }
