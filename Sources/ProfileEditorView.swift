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
    @State private var rssi = "-100"
    @State private var isSkudIdMode = false // НОВОЕ

    var body: some View {
        NavigationView {
            Form {
                Section("Профиль") {
                    TextField("Название (Дом, Офис)", text: $name)
                    Toggle("Вводить SKUD_ID (12 hex)", isOn: $isSkudIdMode)
                }
                Section("Параметры СКУД") {
                    TextField(isSkudIdMode ? "SKUD_ID (напр. 00000001ec36)" : "Service UUID", text: $uuid)
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
                    name = p.name
                    uuid = p.skudUuid
                    keyId = String(p.keyId)
                    token = p.aesToken
                    rssi = String(p.rssiThreshold)
                    isSkudIdMode = p.isSkudIdMode
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
            skudUuid: uuid.trimmingCharacters(in: .whitespaces), // Сохраняем как есть
            keyId: Int(keyId) ?? 0,
            aesToken: token,
            rssiThreshold: Int(rssi) ?? -100,
            isSkudIdMode: isSkudIdMode
        )
        onSave(p)
    }
}
