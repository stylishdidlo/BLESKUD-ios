import Foundation

struct AccessProfile: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var skudUuid: String
    var keyId: Int
    var aesToken: String
    var rssiThreshold: Int
    var isSkudIdMode: Bool = false
}

struct ProfileExport: Codable {
    let version: Int
    let profiles: [AccessProfile]
}
