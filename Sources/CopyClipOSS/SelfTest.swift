import Foundation
import CryptoKit

/// `CopyClipOSS.app/Contents/MacOS/CopyClipOSS --selftest`
/// Exercises the crypto and the biometric keychain path from inside the signed bundle.
enum SelfTest {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--selftest") else { return }
        var failures = 0
        func check(_ name: String, _ f: () throws -> Bool) {
            do { let ok = try f(); print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
            catch { print("FAIL \(name): \(error)"); failures += 1 }
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ccoss-selftest-\(UUID().uuidString)")
        let v = Vault(directory: tmp)
        check("setup + unlock with PIN") {
            try v.setUp(pin: "123456", enableBiometrics: false)
            try v.record(text: "hello", app: "test")
            v.lock()
            try v.unlock(pin: "123456")
            return v.items.first?.text == "hello"
        }
        check("wrong PIN rejected") {
            v.lock()
            do { try v.unlock(pin: "000000"); return false } catch VaultError.wrongPIN { return true }
        }
        check("locked capture goes to inbox, readable after unlock") {
            v.lock()
            try v.record(text: "captured while locked", app: nil)
            let inbox = try FileManager.default.contentsOfDirectory(atPath: v.inboxDir.path)
            guard inbox.count == 1 else { return false }
            let raw = try Data(contentsOf: v.inboxDir.appendingPathComponent(inbox[0]))
            guard !String(decoding: raw, as: UTF8.self).contains("captured") else { return false }
            try v.unlock(pin: "123456")
            let drained = try FileManager.default.contentsOfDirectory(atPath: v.inboxDir.path).isEmpty
            return drained && v.items.first?.text == "captured while locked"
        }
        check("vault file has no plaintext") {
            let raw = try Data(contentsOf: v.bodyURL)
            return !String(decoding: raw, as: UTF8.self).contains("hello")
        }
        if !SecureEnclaveWrap.isAvailable {
            print("SKIP secure enclave wrap: no Touch ID enrolled on this machine (PIN path still works)")
        } else { check("secure enclave wrap (no prompt)") {
            let w = try SecureEnclaveWrap.wrap(dek: Data(repeating: 7, count: 32))
            print("  SE blob bytes: \(w.seKeyBlob.count)")
            return w.seKeyBlob.count > 0 && !w.sealedDEK.elementsEqual(Data(repeating: 7, count: 32))
        } }
        if CommandLine.arguments.contains("--touchid") {
            check("secure enclave unwrap (TOUCH THE SENSOR)") {
                let dek = Crypto.randomBytes(32)
                let w = try SecureEnclaveWrap.wrap(dek: dek)
                guard let back = try SecureEnclaveWrap.unwrap(w, reason: "CopyClip OSS self-test") else {
                    print("  cancelled"); return false
                }
                return back == dek
            }
        }
        try? FileManager.default.removeItem(at: tmp)
        print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
