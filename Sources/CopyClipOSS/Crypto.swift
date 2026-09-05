import Foundation
import CryptoKit
import CommonCrypto

/// All cryptography in one place so it can be audited quickly.
///
/// Design:
/// - DEK  (data encryption key, AES-256-GCM) encrypts the clip history on disk.
/// - The DEK is never stored in plain form. It is stored twice, wrapped:
///     1. wrapped with a KEK derived from the user's PIN (PBKDF2-HMAC-SHA256, 600k rounds)
///     2. wrapped inside the Keychain behind a biometry-only access control (Touch ID)
/// - While the vault is LOCKED the app must still record new clips, but must not be
///   able to read them. So each new clip is sealed to a Curve25519 public key
///   ("inbox"). The matching private key lives inside the encrypted vault, so it is only
///   available after unlock. On unlock the inbox is drained into the vault.
enum Crypto {

    // MARK: PIN -> KEK

    static let pbkdfRounds: UInt32 = 600_000

    static func deriveKEK(pin: String, salt: Data, rounds: UInt32) throws -> SymmetricKey {
        let pinBytes = Array(pin.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltPtr in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                pinBytes.map { CChar(bitPattern: $0) }, pinBytes.count,
                saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                rounds,
                &out, out.count)
        }
        guard status == kCCSuccess else { throw VaultError.crypto("PBKDF2 failed: \(status)") }
        defer { out.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
        return SymmetricKey(data: out)
    }

    // MARK: AES-GCM helpers

    static func seal(_ plaintext: Data, with key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw VaultError.crypto("no combined box") }
        return combined
    }

    static func open(_ combined: Data, with key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    static func randomBytes(_ n: Int) -> Data {
        var d = Data(count: n)
        let r = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, n, $0.baseAddress!) }
        precondition(r == errSecSuccess)
        return d
    }

    // MARK: Inbox (encrypt-to-public-key while locked)

    static let inboxInfo = Data("copyclip-oss-inbox-v1".utf8)

    /// Output layout: [32 bytes ephemeral public key][AES-GCM combined box]
    static func sealToInbox(_ plaintext: Data, recipient: Curve25519.KeyAgreement.PublicKey) throws -> Data {
        let eph = Curve25519.KeyAgreement.PrivateKey()
        let shared = try eph.sharedSecretFromKeyAgreement(with: recipient)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self,
                                                 salt: eph.publicKey.rawRepresentation,
                                                 sharedInfo: inboxInfo,
                                                 outputByteCount: 32)
        return eph.publicKey.rawRepresentation + (try seal(plaintext, with: key))
    }

    static func openFromInbox(_ blob: Data, recipient: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        guard blob.count > 32 else { throw VaultError.crypto("inbox blob too short") }
        let ephPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: blob.prefix(32))
        let shared = try recipient.sharedSecretFromKeyAgreement(with: ephPub)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self,
                                                 salt: ephPub.rawRepresentation,
                                                 sharedInfo: inboxInfo,
                                                 outputByteCount: 32)
        return try open(blob.dropFirst(32), with: key)
    }
}

enum VaultError: LocalizedError {
    case crypto(String)
    case wrongPIN
    case notSetUp
    case locked
    case biometryUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .crypto(let s): return "Crypto error: \(s)"
        case .wrongPIN: return "Wrong PIN"
        case .notSetUp: return "Vault not set up"
        case .locked: return "Vault is locked"
        case .biometryUnavailable(let s): return "Touch ID unavailable: \(s)"
        }
    }
}
