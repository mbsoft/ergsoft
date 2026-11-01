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

    // MARK: Control point (optional; many machines just stream without it)

    private func write(_ op: FTMS.Op, params: [UInt8] = []) {
        guard let cp = controlPoint, let p = erg else { return }
        p.writeValue(Data([op.rawValue] + params), for: cp, type: .withResponse)
    }
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
        p.discoverServices([FTMS.service, HRS.service])
    }

    nonisolated func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        Task { @MainActor in
            if p == erg { ergConnected = false; erg = nil; controlPoint = nil; ergKind = .unknown }
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
                                           FTMS.machineStatus, FTMS.feature], for: s)
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
            if let s = ErgSample.fromRowerData(data) { Task { @MainActor in latest = s; samples.send(s) } }
        case FTMS.indoorBikeData:
            if let s = ErgSample.fromIndoorBikeData(data) { Task { @MainActor in latest = s; samples.send(s) } }
        case HRS.measurement:
            if let hr = ErgSample.heartRate(from: data) {
                Task { @MainActor in if p == hrStrap { strapHeartRate = hr } }
            }
        default: break
        }
    }
}
