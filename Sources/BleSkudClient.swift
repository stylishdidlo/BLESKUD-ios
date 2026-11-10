import Foundation
import CoreBluetooth
import CommonCrypto
import Combine

enum SkudState: Equatable {
    case idle, scanning
    case connecting(String), connected(String, Int), success(String), failed(String)
}

struct ScanFilters {
    var filterByUuidPrefix: Bool = false
    var filterBySkudIdPart: Bool = false
    var filterByServicePresence: Bool = false
    var minRssi: Int = -100
}

final class BleSkudClient: NSObject, ObservableObject {
    static let wUUID = CBUUID(string: "0000F401-0000-1000-8000-00805F9B34FB")
    static let nUUID = CBUUID(string: "0000F402-0000-1000-8000-00805F9B34FB")
    static let ufanetPrefix = "f45389a8-d158-4964-b8ef-"

    @Published private(set) var state: SkudState = .idle
    @Published private(set) var logLines: [String] = []
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
    private var currentFilters = ScanFilters()
    private var currentSkudIdHex: String?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan(profile p: AccessProfile) {
        prof = p; salt = Data(); rssi = 0; isRawScanning = false
        guard central.state == .poweredOn else { return fail("BT off") }
        
        // Сборка UUID, если включен режим SKUD_ID
        let fullUuidStr = p.isSkudIdMode ? "\(Self.ufanetPrefix)\(p.skudUuid.lowercased())" : p.skudUuid
        guard let u = UUID(uuidString: fullUuidStr) else { return fail("Bad UUID format") }
        
        set(.scanning); log("Scan \(fullUuidStr)")
        central.scanForPeripherals(withServices: [CBUUID(nsuuid: u)], options: nil)
        
        to?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let s = self else { return }
            if case .scanning = s.state { s.stopScan(); s.fail("Timeout") }
        }
        to = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: w)
    }
    
    func startScanAll(filters: ScanFilters, skudIdHex: String?) {
        guard central.state == .poweredOn else { return fail("BT off") }
        isRawScanning = true
        currentFilters = filters
        currentSkudIdHex = skudIdHex?.lowercased()
        
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
        
        let rssi = R.intValue
        
        if isRawScanning {
            if rssi < currentFilters.minRssi { return }
            
            // Берем уже распаршенные системой Service UUIDs
            let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
            let uuidStrings = uuids.map { $0.uuidString.lowercased() }
            
            let hasUuid = uuidStrings.contains { $0.hasPrefix(Self.ufanetPrefix) }
            if currentFilters.filterByUuidPrefix && !hasUuid { return }
            
            let hasSkud = if let skud = currentSkudIdHex { uuidStrings.contains { $0.contains(skud) } } else { false }
            if currentFilters.filterBySkudIdPart && !hasSkud { return }
            
            if currentFilters.filterByServicePresence && uuidStrings.isEmpty { return }
            
            let name = p.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
            let displayName = hasUuid ? "⭐ \(name)" : name
            
            if !scannedPeripherals.contains(where: { $0.peripheral.identifier == p.identifier }) {
                DispatchQueue.main.async {
                    self.scannedPeripherals.append((p, displayName, rssi))
                    self.scannedPeripherals.sort { $0.rssi > $1.rssi }
                }
            }
            return
        }
        
        // Обычный режим (по кнопке Start)
        guard let pr = prof, rssi >= pr.rssiThreshold else { return }
        to?.cancel(); stopScan()
        per = p; self.rssi = rssi; p.delegate = self
        set(.connecting(pr.skudUuid)); log("Found \(R)")
        c.connect(p, options: nil)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        log("Connected")
        p.discoverServices(nil) // Ищем сервисы без фильтра
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
