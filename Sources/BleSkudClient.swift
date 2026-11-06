import Foundation
import CoreBluetooth
import CommonCrypto
import Combine

enum SkudState: Equatable {
    case idle, scanning
    case connecting(String), connected(String, Int), success(String), failed(String)
}

final class BleSkudClient: NSObject, ObservableObject {
    static let wUUID = CBUUID(string: "0000F401-0000-1000-8000-00805F9B34FB")
    static let nUUID = CBUUID(string: "0000F402-0000-1000-8000-00805F9B34FB")

    @Published private(set) var state: SkudState = .idle
    @Published private(set) var logLines: [String] = []

    // НОВОЕ: список для UI
    @Published private(set) var scannedPeripherals: [(peripheral: CBPeripheral, name: String, rssi: Int)] = []

    private var central: CBCentralManager!
    private var prof: AccessProfile?
    private var per: CBPeripheral?
    private var wChar: CBCharacteristic?
    private var nChar: CBCharacteristic?
    private var salt = Data()
    private var rssi: Int = 0
    private var to: DispatchWorkItem?
    private var isRawScanning = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan(profile p: AccessProfile) {
        prof = p; salt = Data(); rssi = 0; isRawScanning = false
        guard central.state == .poweredOn else { return fail("BT off") }
        guard let u = UUID(uuidString: p.skudUuid) else { return fail("Bad UUID") }
        set(.scanning); log("Scan \(p.skudUuid)")
        central.scanForPeripherals(withServices: [CBUUID(nsuuid: u)], options: nil)
        to?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let s = self else { return }
            if case .scanning = s.state { s.stopScan(); s.fail("Timeout") }
        }
        to = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: w)
    }

    // НОВОЕ: сканируем всё
    func startScanAll() {
        guard central.state == .poweredOn else { return fail("BT off") }
        isRawScanning = true
        scannedPeripherals.removeAll()
        set(.scanning)
        log("Scanning ALL devices...")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            if self?.isRawScanning == true {
                self?.stopScan()
                self?.set(.idle)
                self?.log("Scan finished")
            }
        }
    }

    // НОВОЕ: прямое подключение
    func connectDirect(peripheral p: CBPeripheral) {
        isRawScanning = false
        stopScan()
        per = p
        p.delegate = self
        set(.connecting(p.identifier.uuidString))
        log("Connecting to \(p.name ?? "Unknown")...")
        central.connect(p, options: nil)
    }

    func stop() {
        to?.cancel(); stopScan()
        if let p = per { central.cancelPeripheralConnection(p) }
        per = nil; wChar = nil; nChar = nil; salt = Data(); set(.idle)
        isRawScanning = false
    }

    func stopScan() { if central.state == .poweredOn { central.stopScan() } }

    func set(_ s: SkudState) { DispatchQueue.main.async { self.state = s } }

    func log(_ s: String) {
        NSLog("[SKUD] %@", s)
        DispatchQueue.main.async {
            self.logLines.append(s)
            if self.logLines.count > 200 { self.logLines = Array(self.logLines.suffix(200)) }
        }
    }

    func fail(_ s: String) { log("FAIL: \(s)"); set(.failed(s)) }

    func buildPayload(_ salt: Data, _ keyId: Int, _ token: String) -> Data? {
        let k = token.data(using: .utf8) ?? Data()
        guard k.count == 16 else { log("AES 16 bytes!"); return nil }
        var p = salt + ("g\(keyId)").data(using: .utf8)!
        if p.count < 16 { p.append(Data(repeating: 0, count: 16 - p.count)) }
        else if p.count > 16 { p = p.prefix(16) }
        return aes(p, k)
    }

    func aes(_ d: Data, _ k: Data) -> Data? {
        let sz = d.count + kCCBlockSizeAES128
        var b = Data(count: sz); var n = 0
        let st = b.withUnsafeMutableBytes { bb in
            d.withUnsafeBytes { dd in
                k.withUnsafeBytes { kk in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                            kk.baseAddress, k.count, nil, dd.baseAddress, d.count, bb.baseAddress, sz, &n)
                }
            }
        }
        guard st == kCCSuccess else { log("CCCrypt \(st)"); return nil }
        return b.prefix(n)
    }

    func sendOpen() {
        guard let p = prof, let w = wChar, let p2 = per,
              let d = buildPayload(salt, p.keyId, p.aesToken) else { return fail("Missing/encrypt") }
        log("Payload: \(d.map { String(format: "%02x", $0) }.joined(separator: " "))")
        p2.writeValue(d, for: w, type: .withResponse)
    }
}

extension BleSkudClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) { log("BT \(c.state.rawValue)") }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi R: NSNumber) {

        // Если это режим "сканировать всё"
        if isRawScanning {
            let rssi = R.intValue
            if rssi < -100 { return }
            let name = p.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"

            if !scannedPeripherals.contains(where: { $0.peripheral.identifier == p.identifier }) {
                DispatchQueue.main.async {
                    self.scannedPeripherals.append((p, name, rssi))
                    self.scannedPeripherals.sort { $0.rssi > $1.rssi }
                }
            }
            return
        }

        // Обычный режим
        guard let pr = prof, R.intValue >= pr.rssiThreshold else { return }
        to?.cancel(); stopScan()
        per = p; rssi = R.intValue; p.delegate = self
        set(.connecting(pr.skudUuid)); log("Found \(R)")
        c.connect(p, options: nil)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        log("Connected")
        // Ищем сервисы без фильтра по UUID (просим всё)
        p.discoverServices(nil)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        fail("Connect: \(error?.localizedDescription ?? "?")")
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        log("Disconnected"); per = nil; wChar = nil; nChar = nil; salt = Data()
    }
}

extension BleSkudClient: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        if let e = error { return fail("Svc: \(e.localizedDescription)") }
        guard let s = p.services, !s.isEmpty else { return fail("No svc") }

        // Просим найти наши характеристики во ВСЕХ сервисах
        for svc in s {
            p.discoverCharacteristics([Self.wUUID, Self.nUUID], for: svc)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        if let e = error { return fail("Chars: \(e.localizedDescription)") }
        for ch in s.characteristics ?? [] {
            if ch.uuid == Self.wUUID { wChar = ch }
            if ch.uuid == Self.nUUID { nChar = ch }
        }

        // Если нашли обе - включаем уведомления
        if let n = nChar, wChar != nil {
            p.setNotifyValue(true, for: n)
            log("Notif on, wait salt")
            set(.connected(prof?.skudUuid ?? "Direct", rssi))
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if let e = error { return fail("Notif: \(e.localizedDescription)") }
        guard ch.uuid == Self.nUUID, let v = ch.value, v.count > 1 else { return }
        salt = v.subdata(in: 1..<v.count)
        log("Salt: \(salt.map { String(format: "%02x", $0) }.joined(separator: " "))")
        sendOpen()
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        if let e = error { fail("Write: \(e.localizedDescription)") }
        else { log("SENT"); set(.success(prof?.skudUuid ?? "Direct")) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.central.cancelPeripheralConnection(p)
        }
    }
}
