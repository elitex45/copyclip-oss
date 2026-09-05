import Foundation
import Combine

/// Owns the vault, the 60-second auto-lock timer, and the UI-facing state.
@MainActor
final class LockManager: ObservableObject {
    enum State: Equatable { case needsSetup, locked, unlocked }

    @Published private(set) var state: State
    @Published private(set) var items: [ClipItem] = []
    @Published var lastError: String?
    @Published private(set) var secondsLeft: Int = 0

    let vault: Vault
    static let unlockSeconds = 60
    private var timer: Timer?

    init(vault: Vault = Vault()) {
        self.vault = vault
        state = vault.isSetUp ? .locked : .needsSetup
    }

    var biometricsAvailable: Bool { vault.biometricEnabled && SecureEnclaveWrap.isAvailable }

    func setUp(pin: String, enableBiometrics: Bool) {
        do {
            try vault.setUp(pin: pin, enableBiometrics: enableBiometrics)
            didUnlock()
        } catch { lastError = error.localizedDescription }
    }

    func unlock(pin: String) {
        do { try vault.unlock(pin: pin); didUnlock() }
        catch { lastError = error.localizedDescription }
    }

    /// Returns true when unlocked.
    @discardableResult
    func unlockWithBiometrics() -> Bool {
        guard biometricsAvailable else { return false }
        do {
            if try vault.unlockWithBiometrics(reason: "Unlock your clipboard history") {
                didUnlock(); return true
            }
        } catch { lastError = error.localizedDescription }
        return false
    }

    func lock() {
        timer?.invalidate(); timer = nil
        vault.lock()
        items = []
        secondsLeft = 0
        if state == .unlocked { state = .locked }
    }

    func touch() {   // reset the 60s window on user activity
        guard state == .unlocked else { return }
        secondsLeft = Self.unlockSeconds
    }

    private func didUnlock() {
        lastError = nil
        state = .unlocked
        items = vault.items
        secondsLeft = Self.unlockSeconds
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.secondsLeft -= 1
                if self.secondsLeft <= 0 { self.lock() }
            }
        }
    }

    // Called by the clipboard watcher in any state.
    func record(text: String, app: String?) {
        do {
            try vault.record(text: text, app: app)
            if state == .unlocked { items = vault.items }
        } catch { lastError = error.localizedDescription }
    }

    func delete(_ item: ClipItem) {
        do { try vault.delete(id: item.id); items = vault.items } catch { lastError = error.localizedDescription }
    }

    func clearAll() {
        do { try vault.clearAll(); items = [] } catch { lastError = error.localizedDescription }
    }

    func changePIN(old: String, new: String) -> Bool {
        do { try vault.changePIN(old: old, new: new); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    func reset() {
        do { try vault.destroy(); items = []; state = .needsSetup } catch { lastError = error.localizedDescription }
    }
}
