import Foundation
import CoreBluetooth
import Combine

/// Advertises the iPhone as a standard BLE Heart Rate sensor (0x180D) so an erg
/// console (Rogue Echo, PM5, etc.) can pair to it like a chest strap and show HR.
@MainActor
final class HRBroadcaster: NSObject, ObservableObject {
    @Published var enabled = false { didSet { enabled ? start() : stop() } }
    @Published private(set) var isAdvertising = false
    @Published private(set) var subscriberCount = 0
    @Published private(set) var lastSent: Int?
    @Published private(set) var status = "Off"

    private var pm: CBPeripheralManager?
    private var measurement: CBMutableCharacteristic?
    private var timer: Timer?
    private var current: Int?

    static let localName = "ErgSoft HR"

    /// Feed the latest HR here (nil = no reading). Sent at 1 Hz while a subscriber is attached.
    func update(heartRate: Int?) { current = heartRate }

    private func start() {
        if pm == nil {
            pm = CBPeripheralManager(delegate: self, queue: .main,
                                     options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
        } else if pm?.state == .poweredOn {
            setupAndAdvertise()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendTick() }
        }
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        pm?.stopAdvertising()
        pm?.removeAllServices()
        isAdvertising = false
        subscriberCount = 0
        status = "Off"
    }

    private func setupAndAdvertise() {
        guard let pm, pm.state == .poweredOn else { return }
        pm.removeAllServices()
        let m = CBMutableCharacteristic(type: HRS.measurement, properties: [.notify], value: nil, permissions: [.readable])
        // Body Sensor Location (0x2A38): 1 = chest — some consoles read it before subscribing.
        let loc = CBMutableCharacteristic(type: CBUUID(string: "2A38"), properties: [.read], value: Data([0x01]), permissions: [.readable])
        let svc = CBMutableService(type: HRS.service, primary: true)
        svc.characteristics = [m, loc]
        measurement = m
        pm.add(svc)
    }

    private func sendTick() {
        guard let pm, let m = measurement, subscriberCount > 0 else { return }
        // Flags 0x00: HR as uint8, no sensor contact info, no energy, no RR.
        // Use uint16 form (flag bit0) if HR > 255 — not realistic, but spec-correct.
        let hr = current ?? 0
        let data: Data = hr > 255 ? Data([0x01, UInt8(hr & 0xFF), UInt8(hr >> 8)]) : Data([0x00, UInt8(hr)])
        if pm.updateValue(data, for: m, onSubscribedCentrals: nil) { lastSent = hr }
    }
}

extension HRBroadcaster: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ p: CBPeripheralManager) {
        Task { @MainActor in
            switch p.state {
            case .poweredOn:
                if enabled { setupAndAdvertise() }
            case .unauthorized: status = "Bluetooth permission denied"
            case .poweredOff:   status = "Bluetooth is off"; isAdvertising = false
            default: break
            }
        }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        Task { @MainActor in
            if let error { status = "Service error: \(error.localizedDescription)"; return }
            p.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [HRS.service],
                                CBAdvertisementDataLocalNameKey: HRBroadcaster.localName])
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ p: CBPeripheralManager, error: Error?) {
        Task { @MainActor in
            if let error { status = "Advertising failed: \(error.localizedDescription)"; return }
            isAdvertising = true
            status = "Advertising as “\(HRBroadcaster.localName)” — pair from the console"
        }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager, central: CBCentral, didSubscribeTo ch: CBCharacteristic) {
        Task { @MainActor in
            subscriberCount += 1
            status = "Console connected — streaming HR"
        }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom ch: CBCharacteristic) {
        Task { @MainActor in
            subscriberCount = max(0, subscriberCount - 1)
            if subscriberCount == 0 { status = "Console disconnected — advertising" }
        }
    }
}
