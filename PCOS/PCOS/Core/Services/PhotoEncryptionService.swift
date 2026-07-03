import Foundation
import CryptoKit
import Security
import os

protocol PhotoEncrypting {
    func encrypt(_ data: Data) -> Data?
    func decrypt(_ data: Data) -> Data?
}

struct PhotoEncryptionService: PhotoEncrypting {
    private static let header = Data("CBENC1".utf8)
    private static let service = "com.cyclebalance.photos"
    private static let account = "photo-encryption-key"
    private static let keyLength = 32

    func encrypt(_ data: Data) -> Data? {
        guard !isEncrypted(data) else { return data }
        guard let key = loadOrCreateKey() else { return nil }

        do {
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { return nil }
            return Self.header + combined
        } catch {
            Logger.photoJournal.error("Photo encryption failed: \(error.localizedDescription)")
            return nil
        }
    }

    func decrypt(_ data: Data) -> Data? {
        guard isEncrypted(data) else { return data }
        guard let key = loadOrCreateKey() else { return nil }

        do {
            let encryptedPayload = Data(data.dropFirst(Self.header.count))
            let box = try AES.GCM.SealedBox(combined: encryptedPayload)
            return try AES.GCM.open(box, using: key)
        } catch {
            Logger.photoJournal.error("Photo decryption failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func isEncrypted(_ data: Data) -> Bool {
        data.starts(with: Self.header)
    }

    private func loadOrCreateKey() -> SymmetricKey? {
        if let existing = loadKeyData() {
            return SymmetricKey(data: existing)
        }

        var bytes = [UInt8](repeating: 0, count: Self.keyLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, Self.keyLength, &bytes)
        guard status == errSecSuccess else { return nil }

        let keyData = Data(bytes)
        guard storeKeyData(keyData) else { return nil }
        return SymmetricKey(data: keyData)
    }

    private func loadKeyData() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func storeKeyData(_ data: Data) -> Bool {
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data,
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess || status == errSecDuplicateItem
    }
}
