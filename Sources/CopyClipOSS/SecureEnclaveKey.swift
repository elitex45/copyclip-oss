import Foundation
import CryptoKit
import LocalAuthentication

/// Touch ID path, backed by the Secure Enclave.
///
/// A P-256 key is generated *inside* the Secure Enclave with an access control of
/// `.biometryCurrentSet`. The private key can never leave the chip, and every use of it
/// requires a Touch ID match enforced by the chip and the OS, not by this app.
///
/// The DEK is wrapped by ECDH: ephemeral P-256 key  x  SE public key -> HKDF -> AES-GCM.
/// Unwrapping needs the SE private key, hence Touch ID. No Keychain, no entitlements,
/// works with an ad-hoc signature.
enum SecureEnclaveWrap {
    static let info = Data("copyclip-oss-se-wrap-v1".utf8)

    struct Wrapped: Codable {
        var seKeyBlob: Data      // opaque, only usable by this Mac's Secure Enclave
        var ephemeralPub: Data   // 64-byte raw P-256 public key
        var sealedDEK: Data      // AES-GCM combined box
    }

    static var isAvailable: Bool {
        guard SecureEnclave.isAvailable else { return false }
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    static func wrap(dek: Data) throws -> Wrapped {
        var cfErr: Unmanaged<CFError>?
        guard let ac = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                       [.privateKeyUsage, .biometryCurrentSet], &cfErr) else {
            throw VaultError.biometryUnavailable(cfErr?.takeRetainedValue().localizedDescription ?? "access control")
        }
        let seKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: ac)
        let eph = P256.KeyAgreement.PrivateKey()
        let shared = try eph.sharedSecretFromKeyAgreement(with: seKey.publicKey)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: eph.publicKey.rawRepresentation,
                                                 sharedInfo: info, outputByteCount: 32)
        return Wrapped(seKeyBlob: seKey.dataRepresentation,
                       ephemeralPub: eph.publicKey.rawRepresentation,
                       sealedDEK: try Crypto.seal(dek, with: key))
    }

    /// Shows the Touch ID prompt. Returns nil if the user cancels or fails biometrics.
    static func unwrap(_ w: Wrapped, reason: String) throws -> Data? {
        let ctx = LAContext()
        ctx.localizedReason = reason
        let seKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: w.seKeyBlob,
                                                                    authenticationContext: ctx)
        let ephPub = try P256.KeyAgreement.PublicKey(rawRepresentation: w.ephemeralPub)
        let shared: SharedSecret
        do {
            shared = try seKey.sharedSecretFromKeyAgreement(with: ephPub)
        } catch {
            let ns = error as NSError
            // User cancelled / no match: LAError domain, or errSecUserCanceled from the SE.
            if ns.domain == LAErrorDomain || ns.code == Int(errSecUserCanceled) || ns.code == Int(errSecAuthFailed) {
                return nil
            }
            if "\(error)".localizedCaseInsensitiveContains("cancel") { return nil }
            throw VaultError.biometryUnavailable("\(error)")
        }
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: w.ephemeralPub,
                                                 sharedInfo: info, outputByteCount: 32)
        return try Crypto.open(w.sealedDEK, with: key)
    }
}
