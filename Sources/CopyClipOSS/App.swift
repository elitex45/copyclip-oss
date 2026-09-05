import SwiftUI
import ServiceManagement

@main
struct CopyClipOSSApp: App {
    init() { SelfTest.runIfRequested() }
    @StateObject private var lock = LockManager()
    @State private var watcher: ClipboardWatcher?
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some Scene {
        MenuBarExtra {
            RootView(lock: lock, watcher: watcherBinding)
                .onAppear { startWatcherIfNeeded() }
        } label: {
            Image(systemName: "paperclip")
        }
        .menuBarExtraStyle(.window)
    }

    private var watcherBinding: ClipboardWatcher {
        if let w = watcher { return w }
        let w = ClipboardWatcher { text, app in lock.record(text: text, app: app) }
        return w
    }

    private func startWatcherIfNeeded() {
        if watcher == nil {
            let w = ClipboardWatcher { text, app in lock.record(text: text, app: app) }
            w.start()
            watcher = w
        }
        if launchAtLogin { try? SMAppService.mainApp.register() }
    }
}

/// Picks the right screen for the current lock state.
struct RootView: View {
    @ObservedObject var lock: LockManager
    let watcher: ClipboardWatcher
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            switch lock.state {
            case .needsSetup: SetupView(lock: lock)
            case .locked: UnlockView(lock: lock)
            case .unlocked: HistoryView(lock: lock, watcher: watcher)
            }
        }
        .onAppear {
            // Opening the menu bar panel while locked triggers Touch ID immediately.
            if lock.state == .locked { lock.unlockWithBiometrics() }
        }
    }
}
