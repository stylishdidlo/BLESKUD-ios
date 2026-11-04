import Foundation
import Security

final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [AccessProfile] = []

    private let profilesKey = "ble_skud_profiles_v1"
    private let tokenService = "com.example.bleskud.token"

    init() {
        load()
    }

    // ─── Load / Save ───
    func load() {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              var list = try? JSONDecoder().decode([AccessProfile].self, from: data)
        else {
            profiles = []
            return
        }
        for i in list.indices {
            if let tok = Keychain.load(service: tokenService, account: list[i].id),
               let str = String(data: tok, encoding: .utf8) {
                list[i].aesToken = str
            }
        }
        profiles = list
    }

    func upsert(_ p: AccessProfile) {
        var copy = p
        if let tokData = copy.aesToken.data(using: .utf8) {
            Keychain.save(service: tokenService, account: copy.id, data: tokData)
        }
        copy.aesToken = ""
        var list = profiles
        if let idx = list.firstIndex(where: { $0.id == copy.id }) {
            list[idx] = copy
        } else {
            list.append(copy)
        }
        persist(list)
    }

    func delete(id: String) {
        Keychain.delete(service: tokenService, account: id)
        persist(profiles.filter { $0.id != id })
    }

    private func persist(_ list: [AccessProfile]) {
        var toPublish = list
        for i in toPublish.indices {
            if let tok = Keychain.load(service: tokenService, account: toPublish[i].id),
               let str = String(data: tok, encoding: .utf8) {
                toPublish[i].aesToken = str
            }
        }
        profiles = toPublish
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
    }

    // ─── Import / Export ───
    func exportJSON() -> String {
        let payload = ProfileExport(version: 1, profiles: profiles)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        guard let data = try? enc.encode(payload) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func importJSON(_ json: String) -> Result<Int, Error> {
        guard let data = json.data(using: .utf8) else {
            return .failure(NSError(domain: "profile", code: 1))
        }
        do {
            let wrapper = try JSONDecoder().decode(ProfileExport.self, from: data)
            var added = 0
            for var p in wrapper.profiles {
                let exists = profiles.contains { $0.skudUuid == p.skudUuid && $0.keyId == p.keyId }
                if exists { continue }
                p.id = UUID().uuidString
                upsert(p)
                added += 1
            }
            return .success(added)
        } catch {
            return .failure(error)
        }
    }
}

// ─── Keychain helper ───
enum Keychain {
    static func save(service: String, account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
