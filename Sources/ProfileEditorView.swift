import SwiftUI

struct ProfileEditorView: View {
    let profile: AccessProfile?
    let onSave: (AccessProfile) -> Void
    let onCancel: () -> Void
    let onDelete: (() -> Void)?

    @State private var name = ""
    @State private var uuid = ""
    @State private var keyId = ""
    @State private var token = ""
    @State private var rssi = "-70"

    var body: some View {
        NavigationView {
            Form {
                Section("Профиль") {
                    TextField("Название (Дом, Офис)", text: $name)
                }
                Section("Параметры СКУД") {
                    TextField("Service UUID", text: $uuid)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    TextField("Key ID", text: $keyId)
                        .keyboardType(.numberPad)
                    TextField("AES token (16 симв.)", text: $token)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    TextField("RSSI threshold", text: $rssi)
                        .keyboardType(.numbersAndPunctuation)
                }
                if onDelete != nil {
                    Section {
                        Button("Удалить профиль", role: .destructive) {
                            onDelete?()
                        }
                    }
                }
            }
            .navigationTitle(profile == nil ? "Новый профиль" : "Редактировать")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear {
                if let p = profile {
                    name = p.name; uuid = p.skudUuid; keyId = String(p.keyId)
                    token = p.aesToken; rssi = String(p.rssiThreshold)
                }
            }
        }
    }

    private var isValid: Bool {
        !name.isEmpty &&
        Int(keyId) != nil &&
        token.count == 16 &&
        !uuid.isEmpty
    }

    private func save() {
        let p = AccessProfile(
            id: profile?.id ?? UUID().uuidString,
            name: name,
            skudUuid: normalizeUuid(uuid),
            keyId: Int(keyId) ?? 0,
            aesToken: token,
            rssiThreshold: Int(rssi) ?? -70
        )
        onSave(p)
    }

    private func normalizeUuid(_ raw: String) -> String {
        let hex = raw.replacingOccurrences(of: "-", with: "").lowercased()
        let padded = hex.padding(toLength: 32, withPad: "0", startingAt: 0)
        let p = Array(padded.prefix(32))
        return "\(String(p[0..<8]))-\(String(p[8..<12]))-\(String(p[12..<16]))-\(String(p[16..<20]))-\(String(p[20..<32]))"
    }
}
