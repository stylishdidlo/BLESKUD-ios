import Foundation

struct AccessProfile: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var skudUuid: String
    var keyId: Int
    var aesToken: String
    var rssiThreshold: Int
}

struct ProfileExport: Codable {
    let version: Int
    let profiles: [AccessProfile]
}
