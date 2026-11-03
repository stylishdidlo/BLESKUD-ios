import SwiftUI

struct ContentView: View {
    @StateObject private var c = BleSkudClient()
    @State private var uuid  = "00000002-5BB2-0000-0000-000000000000"
    @State private var keyId = "3891637"
    @State private var token = "pcjhp6060px38f9b"
    @State private var rssi  = "-70"

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fld("UUID", $uuid, .default)
                    fld("KeyID", $keyId, .numberPad)
                    fld("AES", $token, .default)
                    fld("RSSI", $rssi, .numbersAndPunctuation)
                    HStack(spacing: 12) {
                        Button("Start") { go() }.buttonStyle(.borderedProminent)
                        Button("Stop") { c.stop() }.buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity).padding(.top, 8)
                    Text(st).font(.headline)
                    Divider()
                    Text(c.logLines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding()
            }.navigationTitle("BLE SKUD")
        }
    }

    func fld(_ t: String, _ b: Binding<String>, _ kb: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.caption).foregroundColor(.secondary)
            TextField(t, text: b).keyboardType(kb)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
        }
    }

    func go() {
        guard let k = Int(keyId), let r = Int(rssi) else { return }
        c.startScan(profile: AccessProfile(name: "T", skudUuid: uuid, keyId: k, aesToken: token, rssiThreshold: r))
    }

    var st: String {
        switch c.state {
        case .idle: return "Idle"
        case .scanning: return "Scanning..."
        case .connecting(let u): return "Connect \(u)"
        case .connected(let u, let r): return "OK \(u) \(r)"
        case .success: return "OPEN SIGNAL SENT"
        case .failed(let r): return "FAIL: \(r)"
        }
    }
}
