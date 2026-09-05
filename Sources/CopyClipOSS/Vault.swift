import Foundation
import CryptoKit

struct ClipItem: Codable, Identifiable, Equatable {
    var id: UUID
    var text: String
    var date: Date
    var app: String?
}

/// Public, unencrypted header. Contains only wrapped keys and salts.
struct VaultHeader: Codable {
    var version = 1
    var salt: Data
    var rounds: UInt32
    var pinWrappedDEK: Data          // AES-GCM(KEK_pin, DEK)
    var inboxPublicKey: Data         // Curve25519 raw public key
    var seWrappedDEK: SecureEnclaveWrap.Wrapped?   // Touch ID path, nil if disabled
}

/// Encrypted body. Only readable with the DEK.
struct VaultBody: Codable {
    var inboxPrivateKey: Data        // Curve25519 raw private key
    var items: [ClipItem]
}

/// On-disk layout in ~/Library/Application Support/CopyClipOSS/
///   header.json        public header
///   vault.enc          AES-GCM(DEK, VaultBody JSON)
///   inbox/<uuid>.bin   clips captured while locked, sealed to inboxPublicKey
final class Vault {
    let dir: URL
    private var header: VaultHeader?
    private var dek: SymmetricKey?          // present only while unlocked
    private var body: VaultBody?            // present only while unlocked

    init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = directory ?? base.appendingPathComponent("CopyClipOSS", isDirectory: true)
        try? FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        header = try? JSONDecoder().decode(VaultHeader.self, from: Data(contentsOf: headerURL))
    }

    var headerURL: URL { dir.appendingPathComponent("header.json") }
    var bodyURL: URL { dir.appendingPathComponent("vault.enc") }
    var inboxDir: URL { dir.appendingPathComponent("inbox", isDirectory: true) }

    var isSetUp: Bool { header != nil }
    var isUnlocked: Bool { dek != nil && body != nil }
    var biometricEnabled: Bool { header?.seWrappedDEK != nil }

    // MARK: Setup

    func setUp(pin: String, enableBiometrics: Bool) throws {
        let dekData = Crypto.randomBytes(32)
        let dek = SymmetricKey(data: dekData)
        let salt = Crypto.randomBytes(16)
        let kek = try Crypto.deriveKEK(pin: pin, salt: salt, rounds: Crypto.pbkdfRounds)
        let inboxKey = Curve25519.KeyAgreement.PrivateKey()

        var se: SecureEnclaveWrap.Wrapped?
        if enableBiometrics {
            do { se = try SecureEnclaveWrap.wrap(dek: dekData) }
            catch { NSLog("Secure Enclave enrol failed: \(error)") }
        }

        let h = VaultHeader(salt: salt, rounds: Crypto.pbkdfRounds,
                            pinWrappedDEK: try Crypto.seal(dekData, with: kek),
                            inboxPublicKey: inboxKey.publicKey.rawRepresentation,
                            seWrappedDEK: se)
        let b = VaultBody(inboxPrivateKey: inboxKey.rawRepresentation, items: [])
        header = h
        self.dek = dek
        body = b
        try persistHeader()
        try persistBody()
    }

    // MARK: Unlock / lock

    func unlock(pin: String) throws {
        guard let h = header else { throw VaultError.notSetUp }
        let kek = try Crypto.deriveKEK(pin: pin, salt: h.salt, rounds: h.rounds)
        let dekData: Data
        do { dekData = try Crypto.open(h.pinWrappedDEK, with: kek) }
        catch { throw VaultError.wrongPIN }
        try finishUnlock(dekData: dekData)
    }

    /// Returns false if the user cancelled the Touch ID prompt.
    func unlockWithBiometrics(reason: String) throws -> Bool {
        guard let h = header else { throw VaultError.notSetUp }
        guard let w = h.seWrappedDEK else { throw VaultError.biometryUnavailable("not enrolled") }
        guard let dekData = try SecureEnclaveWrap.unwrap(w, reason: reason) else { return false }
        try finishUnlock(dekData: dekData)
        return true
    }

    private func finishUnlock(dekData: Data) throws {
        let key = SymmetricKey(data: dekData)
        let raw = try Data(contentsOf: bodyURL)
        let plain = try Crypto.open(raw, with: key)
        var b = try JSONDecoder().decode(VaultBody.self, from: plain)
        dek = key
        // Drain inbox
        let priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: b.inboxPrivateKey)
        let files = (try? FileManager.default.contentsOfDirectory(at: inboxDir, includingPropertiesForKeys: nil)) ?? []
        var pulled: [ClipItem] = []
        for f in files where f.pathExtension == "bin" {
            if let blob = try? Data(contentsOf: f),
               let plain = try? Crypto.openFromInbox(blob, recipient: priv),
               let item = try? JSONDecoder().decode(ClipItem.self, from: plain) {
                pulled.append(item)
            }
            try? FileManager.default.removeItem(at: f)
        }
        if !pulled.isEmpty {
            b.items = Vault.merge(existing: b.items, new: pulled.sorted { $0.date < $1.date })
        }
        body = b
        if !pulled.isEmpty { try persistBody() }
    }

    func lock() {
        dek = nil
        body = nil
    }

    // MARK: Items

    var items: [ClipItem] { body?.items ?? [] }

    var maxItems: Int {
        get { UserDefaults.standard.object(forKey: "maxItems") as? Int ?? 100 }
        set { UserDefaults.standard.set(newValue, forKey: "maxItems") }
    }

    /// Works whether locked or unlocked. Locked -> sealed into the inbox.
    func record(text: String, app: String?) throws {
        let item = ClipItem(id: UUID(), text: text, date: Date(), app: app)
        if var b = body, dek != nil {
            b.items = Vault.merge(existing: b.items, new: [item])
            b.items = Array(b.items.prefix(maxItems))
            body = b
            try persistBody()
        } else if let h = header {
            let pub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: h.inboxPublicKey)
            let blob = try Crypto.sealToInbox(try JSONEncoder().encode(item), recipient: pub)
            let url = inboxDir.appendingPathComponent(item.id.uuidString + ".bin")
            try blob.write(to: url, options: [.atomic, .completeFileProtection])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    func delete(id: UUID) throws {
        guard var b = body else { throw VaultError.locked }
        b.items.removeAll { $0.id == id }
        body = b
        try persistBody()
    }

    func clearAll() throws {
        guard var b = body else { throw VaultError.locked }
        b.items = []
        body = b
        try persistBody()
    }

    func changePIN(old: String, new: String) throws {
        guard let h = header else { throw VaultError.notSetUp }
        let oldKek = try Crypto.deriveKEK(pin: old, salt: h.salt, rounds: h.rounds)
        let dekData: Data
        do { dekData = try Crypto.open(h.pinWrappedDEK, with: oldKek) } catch { throw VaultError.wrongPIN }
        let salt = Crypto.randomBytes(16)
        let kek = try Crypto.deriveKEK(pin: new, salt: salt, rounds: Crypto.pbkdfRounds)
        var nh = h
        nh.salt = salt
        nh.rounds = Crypto.pbkdfRounds
        nh.pinWrappedDEK = try Crypto.seal(dekData, with: kek)
        header = nh
        try persistHeader()
    }

    /// Newest first, de-duplicated by text (a re-copied item moves to the top).
    static func merge(existing: [ClipItem], new: [ClipItem]) -> [ClipItem] {
        var out = existing
        for n in new {
            out.removeAll { $0.text == n.text }
            out.insert(n, at: 0)
        }
        return out
    }

    // MARK: Persist

    private func persistHeader() throws {
        guard let h = header else { return }
        let data = try JSONEncoder().encode(h)
        try data.write(to: headerURL, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: headerURL.path)
    }

    private func persistBody() throws {
        guard let b = body, let key = dek else { throw VaultError.locked }
        let plain = try JSONEncoder().encode(b)
        let sealed = try Crypto.seal(plain, with: key)
        try sealed.write(to: bodyURL, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bodyURL.path)
    }

    /// Destroys everything. Used by "Reset vault".
    func destroy() throws {
        lock()
        header = nil
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }
}
