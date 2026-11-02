import Foundation
import CoreBluetooth
import Combine

struct DiscoveredDevice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let rssi: Int
    let isHeartRateOnly: Bool
}

/// Owns the CoreBluetooth central, discovers FTMS machines and HR straps,
/// and publishes decoded samples.
@MainActor
final class BLEManager: NSObject, ObservableObject {
    @Published var isPoweredOn = false
    @Published var isScanning = false
    @Published var devices: [DiscoveredDevice] = []

    @Published var erg: CBPeripheral?
    @Published var ergName: String = ""
    @Published var ergKind: ErgKind = .unknown
    @Published var ergConnected = false
    @Published var latest = ErgSample()

    @Published var hrStrap: CBPeripheral?
    @Published var hrStrapConnected = false
    @Published var strapHeartRate: Int?

    /// Fires for every decoded machine notification.
    let samples = PassthroughSubject<ErgSample, Never>()

    enum MachineEvent { case started, paused, stopped, reset }
    /// Console-originated state changes (user pressed a button or the flywheel started/stopped).
    let machineEvents = PassthroughSubject<MachineEvent, Never>()

    // Diagnostics
    @Published var feature: FTMS.Feature?
    @Published var trainingStatus: String = "—"
    @Published var machineStatus: String = "—"
    @Published var powerRange: String = "—"
    @Published var resistanceRange: String = "—"
    @Published var controlPointLog: [String] = []
    @Published var eventLog: [String] = []
    @Published var packetsPerSecond: Double = 0
    private var packetTimes: [Date] = []

    private func log(_ s: String) {
        let t = Date().formatted(date: .omitted, time: .standard)
        eventLog.insert("\(t)  \(s)", at: 0)
        if eventLog.count > 200 { eventLog.removeLast() }
    }

    private var central: CBCentralManager!
    private var seen: [UUID: CBPeripheral] = [:]
    private var controlPoint: CBCharacteristic?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: Scanning

    func startScan() {
        guard isPoweredOn else { return }
        devices = []
        seen = [:]
        isScanning = true
        central.scanForPeripherals(withServices: [FTMS.service, HRS.service],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    // MARK: Connecting

    func connect(_ device: DiscoveredDevice) {
        guard let p = seen[device.id] else { return }
        stopScan()
        if device.isHeartRateOnly {
            hrStrap = p
        } else {
            erg = p
            ergName = device.name
        }
        p.delegate = self
        central.connect(p, options: nil)
    }

    func disconnectErg() {
        if let p = erg { central.cancelPeripheralConnection(p) }
    }

    func disconnectStrap() {
        if let p = hrStrap { central.cancelPeripheralConnection(p) }
    }

    private func notePacket() {
        let now = Date()
        packetTimes.append(now)
        packetTimes.removeAll { now.timeIntervalSince($0) > 5 }
        packetsPerSecond = Double(packetTimes.count) / 5.0
    }

    // MARK: Control point (optional; many machines just stream without it)

    private func write(_ op: FTMS.Op, params: [UInt8] = []) {
        guard let cp = controlPoint, let p = erg else { return }
        p.writeValue(Data([op.rawValue] + params), for: cp, type: .withResponse)
        log("Control point write: \(op)")
    }
    func setTargetPower(_ w: Int) { guard let cp = controlPoint, let p = erg else { return }; p.writeValue(Data([0x05, UInt8(w & 0xFF), UInt8(w >> 8)]), for: cp, type: .withResponse); log("Set target power \(w) W") }
    func setTargetHeartRate(_ bpm: Int) { guard let cp = controlPoint, let p = erg else { return }; p.writeValue(Data([0x06, UInt8(bpm)]), for: cp, type: .withResponse); log("Set target HR \(bpm)") }
    func requestControl() { write(.requestControl) }
    func startMachine()   { write(.startOrResume) }
    func stopMachine()    { write(.stopOrPause, params: [0x01]) }
    func resetMachine()   { write(.reset) }
}

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ c: CBCentralManager) {
        Task { @MainActor in
            isPoweredOn = c.state == .poweredOn
            if !isPoweredOn { isScanning = false; ergConnected = false; hrStrapConnected = false }
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                                    advertisementData: [String: Any], rssi: NSNumber) {
        let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? "Unknown"
        let hrOnly = uuids.contains(HRS.service) && !uuids.contains(FTMS.service)
        let d = DiscoveredDevice(id: p.identifier, name: name, rssi: rssi.intValue, isHeartRateOnly: hrOnly)
        Task { @MainActor in
            seen[p.identifier] = p
            if let i = devices.firstIndex(where: { $0.id == d.id }) { devices[i] = d } else { devices.append(d) }
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        Task { @MainActor in log("Connected \(p.name ?? "")") }
        p.discoverServices([FTMS.service, HRS.service])
    }

    nonisolated func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        Task { @MainActor in
            if p == erg { ergConnected = false; erg = nil; controlPoint = nil; ergKind = .unknown; log("Erg disconnected \(error.map { $0.localizedDescription } ?? "")") }
            if p == hrStrap { hrStrapConnected = false; hrStrap = nil; strapHeartRate = nil }
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        Task { @MainActor in
            if p == erg { erg = nil }
            if p == hrStrap { hrStrap = nil }
        }
    }
}

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] {
            if s.uuid == FTMS.service {
                p.discoverCharacteristics([FTMS.rowerData, FTMS.indoorBikeData, FTMS.controlPoint,
                                           FTMS.machineStatus, FTMS.feature, FTMS.trainingStatus,
                                           FTMS.supportedPowerRange, FTMS.supportedResistanceRange], for: s)
            } else if s.uuid == HRS.service {
                p.discoverCharacteristics([HRS.measurement], for: s)
            }
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            switch ch.uuid {
            case FTMS.rowerData:
                p.setNotifyValue(true, for: ch)
                Task { @MainActor in ergKind = .rower; ergConnected = true }
            case FTMS.indoorBikeData:
                p.setNotifyValue(true, for: ch)
                Task { @MainActor in ergKind = .bike; ergConnected = true }
            case FTMS.controlPoint:
                p.setNotifyValue(true, for: ch)
                Task { @MainActor in controlPoint = ch; requestControl() }
            case FTMS.machineStatus:
                p.setNotifyValue(true, for: ch)
            case FTMS.trainingStatus:
                p.setNotifyValue(true, for: ch); p.readValue(for: ch)
            case FTMS.feature, FTMS.supportedPowerRange, FTMS.supportedResistanceRange:
                p.readValue(for: ch)
            case HRS.measurement:
                p.setNotifyValue(true, for: ch)
                Task { @MainActor in if p == hrStrap { hrStrapConnected = true } }
            default: break
            }
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let data = ch.value else { return }
        switch ch.uuid {
        case FTMS.rowerData:
            if let s = ErgSample.fromRowerData(data) { Task { @MainActor in notePacket(); latest = s; samples.send(s) } }
        case FTMS.indoorBikeData:
            if let s = ErgSample.fromIndoorBikeData(data) { Task { @MainActor in notePacket(); latest = s; samples.send(s) } }
        case FTMS.feature:
            Task { @MainActor in feature = FTMS.Feature(data); log("Feature: " + data.map { String(format: "%02X", $0) }.joined()) }
        case FTMS.trainingStatus:
            let t = FTMS.trainingStatusText(data); Task { @MainActor in trainingStatus = t; log("Training status: \(t)") }
        case FTMS.machineStatus:
            let t = FTMS.machineStatusText(data)
            let ev: MachineEvent? = {
                switch data.first {
                case 0x01: return .reset
                case 0x02: return data.count > 1 && data[1] == 0x02 ? .paused : .stopped
                case 0x04: return .started
                default: return nil
                }
            }()
            Task { @MainActor in machineStatus = t; log("Machine status: \(t)"); if let ev { machineEvents.send(ev) } }
        case FTMS.controlPoint:
            let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            Task { @MainActor in controlPointLog.insert(hex, at: 0); log("Control point response: \(hex)") }
        case FTMS.supportedPowerRange:
            var r = ByteReader(data); if let a = r.s16(), let b = r.s16(), let st = r.u16() { Task { @MainActor in powerRange = "\(a)–\(b) W, step \(st)" } }
        case FTMS.supportedResistanceRange:
            var r = ByteReader(data); if let a = r.s16(), let b = r.s16(), let st = r.u16() { Task { @MainActor in resistanceRange = "\(Double(a)/10)–\(Double(b)/10), step \(Double(st)/10)" } }
        case HRS.measurement:
            if let hr = ErgSample.heartRate(from: data) {
                Task { @MainActor in if p == hrStrap { strapHeartRate = hr } }
            }
        default: break
        }
    }
}
