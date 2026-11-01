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

    /// Rower Data characteristic (0x2AD1), FTMS 4.9.
    static func fromRowerData(_ d: Data) -> ErgSample? {
        var r = ByteReader(d)
        guard let flags = r.u16() else { return nil }
        var s = ErgSample()
        let moreData = flags & (1 << 0) != 0
        if !moreData {
            if let sr = r.u8() { s.strokeRate = Double(sr) / 2.0 }
            if let sc = r.u16() { s.strokeCount = Int(sc) }
        }
        if flags & (1 << 1) != 0 { _ = r.u8() }                                        // average stroke rate
        if flags & (1 << 2) != 0, let m = r.u24() { s.distanceMeters = Double(m) }
        if flags & (1 << 3) != 0, let p = r.u16() { s.paceSecondsPer500m = p == 0xFFFF ? nil : Double(p) }
        if flags & (1 << 4) != 0 { _ = r.u16() }                                       // average pace
        if flags & (1 << 5) != 0, let w = r.s16() { s.powerWatts = Int(w) }
        if flags & (1 << 6) != 0, let w = r.s16() { s.averagePowerWatts = Int(w) }
        if flags & (1 << 7) != 0, let l = r.s16() { s.resistanceLevel = Int(l) }
        if flags & (1 << 8) != 0 {
            if let t = r.u16() { s.caloriesTotal = t == 0xFFFF ? nil : Int(t) }
            if let h = r.u16() { s.caloriesPerHour = h == 0xFFFF ? nil : Int(h) }
            _ = r.u8()                                                                  // per minute
        }
        if flags & (1 << 9) != 0, let hr = r.u8(), hr > 0 { s.heartRate = Int(hr) }
        if flags & (1 << 10) != 0 { _ = r.u8() }                                       // MET
        if flags & (1 << 11) != 0, let t = r.u16() { s.elapsedSeconds = Int(t) }
        if flags & (1 << 12) != 0, let t = r.u16() { s.remainingSeconds = Int(t) }
        return s
    }

    /// Indoor Bike Data characteristic (0x2AD2), FTMS 4.9.
    static func fromIndoorBikeData(_ d: Data) -> ErgSample? {
        var r = ByteReader(d)
        guard let flags = r.u16() else { return nil }
        var s = ErgSample()
        let moreData = flags & (1 << 0) != 0
        if !moreData, let v = r.u16() { s.speedKph = Double(v) / 100.0 }
        if flags & (1 << 1) != 0 { _ = r.u16() }                                       // average speed
        if flags & (1 << 2) != 0, let c = r.u16() { s.strokeRate = Double(c) / 2.0 }   // cadence rpm
        if flags & (1 << 3) != 0 { _ = r.u16() }                                       // average cadence
        if flags & (1 << 4) != 0, let m = r.u24() { s.distanceMeters = Double(m) }
        if flags & (1 << 5) != 0, let l = r.s16() { s.resistanceLevel = Int(l) }
        if flags & (1 << 6) != 0, let w = r.s16() { s.powerWatts = Int(w) }
        if flags & (1 << 7) != 0, let w = r.s16() { s.averagePowerWatts = Int(w) }
        if flags & (1 << 8) != 0 {
            if let t = r.u16() { s.caloriesTotal = t == 0xFFFF ? nil : Int(t) }
            if let h = r.u16() { s.caloriesPerHour = h == 0xFFFF ? nil : Int(h) }
            _ = r.u8()
        }
        if flags & (1 << 9) != 0, let hr = r.u8(), hr > 0 { s.heartRate = Int(hr) }
        if flags & (1 << 10) != 0 { _ = r.u8() }
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
