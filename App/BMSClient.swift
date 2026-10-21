import AppKit
import CoreBluetooth
import WidgetKit

struct DiscoveredDevice: Identifiable {
    let id: UUID
    let name: String
    var rssi: Int
    let peripheral: CBPeripheral
}

/// Owns the BLE connection to a JBD BMS, polls it, and publishes snapshots
/// to the menu bar UI and (through SnapshotStore) to the widget.
final class BMSClient: NSObject, ObservableObject {
    enum State: Equatable {
        case starting, bluetoothOff, unauthorized, scanning, connecting, connected
    }

    enum Issue {
        case noBMSService
    }

    @Published private(set) var state: State = .starting
    @Published private(set) var snapshot: BMSSnapshot?
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var deviceName: String?
    @Published private(set) var issue: Issue?

    private static let services = [CBUUID(string: "FF00"), CBUUID(string: "FFE0")]
    private static let savedDeviceKey = "bms.peripheral.id"
    private let pollInterval: TimeInterval = 10
    private let widgetReloadInterval: TimeInterval = 60
    private let reconnectDelay: TimeInterval = 3

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var assembler = JBDFrameAssembler()
    private var pollTimer: Timer?
    private var lastWidgetReload = Date.distantPast

    override init() {
        super.init()
        snapshot = SnapshotStore.load()
        central = CBCentralManager(delegate: self, queue: .main)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate),
                                               name: NSApplication.willTerminateNotification, object: nil)
    }

    // MARK: - Actions from the UI

    func select(_ device: DiscoveredDevice) {
        central.stopScan()
        UserDefaults.standard.set(device.id.uuidString, forKey: Self.savedDeviceKey)
        connect(device.peripheral)
    }

    func forgetDevice() {
        stopPolling()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        deviceName = nil
        UserDefaults.standard.removeObject(forKey: Self.savedDeviceKey)
        startScan()
    }

    // MARK: - Connection

    private func begin() {
        if let saved = UserDefaults.standard.string(forKey: Self.savedDeviceKey),
           let id = UUID(uuidString: saved),
           let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(known)
        } else {
            startScan()
        }
    }

    private func startScan() {
        devices = []
        state = .scanning
        central.scanForPeripherals(withServices: nil)
    }

    private func connect(_ target: CBPeripheral) {
        peripheral = target
        target.delegate = self
        deviceName = target.name
        issue = nil
        state = .connecting
        central.connect(target)   // stays pending until the BMS is in range
    }

    private func reconnect(_ target: CBPeripheral) {
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
            guard let self, self.peripheral?.identifier == target.identifier else { return }
            self.central.connect(target)
        }
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func poll() {
        assembler.reset()
        send(.basicInfo)
    }

    private func send(_ command: JBDCommand) {
        guard let peripheral, let characteristic = writeCharacteristic else { return }
        let type: CBCharacteristicWriteType =
            characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(JBDProtocol.request(command), for: characteristic, type: type)
    }

    private func handle(_ data: Data) {
        for bytes in assembler.feed(data) {
            guard let frame = try? JBDProtocol.decode(bytes), frame.status == 0 else { continue }

            switch frame.command {
            case JBDCommand.basicInfo.rawValue:
                guard var next = try? JBDProtocol.basicInfo(from: frame.payload) else { continue }
                next.cellVoltages = snapshot?.cellVoltages ?? []
                publish(next)
                send(.cellVoltages)

            case JBDCommand.cellVoltages.rawValue:
                guard var current = snapshot else { continue }
                current.cellVoltages = JBDProtocol.cellVoltages(from: frame.payload)
                publish(current)

            default:
                break
            }
        }
    }

    private func publish(_ next: BMSSnapshot) {
        let previous = snapshot
        snapshot = next
        SnapshotStore.save(next)

        // WidgetKit rations reloads, so push on meaningful change or once per interval.
        let changed = previous.map { $0.percent != next.percent || $0.isCharging != next.isCharging } ?? true
        if changed || Date().timeIntervalSince(lastWidgetReload) >= widgetReloadInterval {
            lastWidgetReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Quit

    /// Quitting drops the BLE link, so flag the last reading and tell the widget right away
    /// instead of letting it go stale.
    @objc private func applicationWillTerminate() {
        guard var last = snapshot else { return }
        last.disconnected = true
        SnapshotStore.save(last)
        WidgetCenter.shared.reloadAllTimelines()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))   // let the reload request go out
    }
}

// MARK: - CBCentralManagerDelegate

extension BMSClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: begin()
        case .poweredOff: stopPolling(); state = .bluetoothOff
        case .unauthorized: state = .unauthorized
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover discovered: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? discovered.name
        guard let name, !name.isEmpty else { return }

        let device = DiscoveredDevice(id: discovered.identifier, name: name,
                                      rssi: RSSI.intValue, peripheral: discovered)
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
        devices.sort { $0.rssi > $1.rssi }
    }

    func centralManager(_ central: CBCentralManager, didConnect connected: CBPeripheral) {
        deviceName = connected.name ?? deviceName
        connected.discoverServices(Self.services)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect failed: CBPeripheral, error: Error?) {
        reconnect(failed)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral dropped: CBPeripheral, error: Error?) {
        stopPolling()
        writeCharacteristic = nil
        guard dropped.identifier == peripheral?.identifier else { return }
        state = .connecting
        reconnect(dropped)
    }
}

// MARK: - CBPeripheralDelegate

extension BMSClient: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services, !services.isEmpty else {
            issue = .noBMSService
            return
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        var notify: CBCharacteristic?
        var write: CBCharacteristic?

        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid.uuidString {
            case "FF01": notify = characteristic
            case "FF02": write = characteristic
            case "FFE1": notify = characteristic; write = characteristic
            default: break
            }
        }
        guard let notify, let write else { return }

        writeCharacteristic = write
        peripheral.setNotifyValue(true, for: notify)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, characteristic.isNotifying else { return }
        issue = nil
        state = .connected
        startPolling()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        handle(data)
    }
}
