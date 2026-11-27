import Foundation
import Security

/// Secrets live only in the iOS Keychain (this device only), never in the repo or build files.
enum Keychain {
    static let authKey = "maps4miband-authkey"
    static let vietmapKey = "maps4miband-vietmap"

    private static func query(_ service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    static func load(_ service: String) -> String? {
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query(service).merging([kSecReturnData as String: true]) { $1 } as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String, as service: String) -> Bool {
        SecItemDelete(query(service) as CFDictionary)
        let item = query(service).merging([
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]) { $1 }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
