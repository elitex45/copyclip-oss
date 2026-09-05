import SwiftUI
import AppKit
import ServiceManagement

private let panelWidth: CGFloat = 300

// MARK: - Setup

struct SetupView: View {
    @ObservedObject var lock: LockManager
    @State private var pin = ""
    @State private var confirm = ""
    @State private var useTouchID = SecureEnclaveWrap.isAvailable

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "paperclip").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("Choose a PIN").font(.headline)
            SecureField("PIN, 6 or more", text: $pin).textFieldStyle(.roundedBorder)
            SecureField("Again", text: $confirm).textFieldStyle(.roundedBorder)
                .onSubmit(create)
            if SecureEnclaveWrap.isAvailable {
                Toggle("Use Touch ID", isOn: $useTouchID).toggleStyle(.switch).controlSize(.small)
            }
            if let e = lock.lastError { Text(e).font(.caption).foregroundStyle(.red) }
            Button("Create", action: create)
                .keyboardShortcut(.defaultAction)
                .disabled(pin.count < 6 || pin != confirm)
        }
        .padding(20)
        .frame(width: panelWidth)
    }

    private func create() { lock.setUp(pin: pin, enableBiometrics: useTouchID) }
}

// MARK: - Unlock

struct UnlockView: View {
    @ObservedObject var lock: LockManager
    @State private var pin = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            if lock.biometricsAvailable {
                Button { lock.unlockWithBiometrics() } label: {
                    Image(systemName: "touchid").font(.system(size: 34)).foregroundStyle(.pink)
                }
                .buttonStyle(.plain).help("Touch ID")
            } else {
                Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(.secondary)
            }
            SecureField("PIN", text: $pin)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .focused($focused)
                .onSubmit { lock.unlock(pin: pin); pin = "" }
            if let e = lock.lastError { Text(e).font(.caption).foregroundStyle(.red) }
        }
        .padding(20)
        .frame(width: panelWidth)
        .onAppear { focused = true }
    }
}

// MARK: - History

struct HistoryView: View {
    @ObservedObject var lock: LockManager
    let watcher: ClipboardWatcher
    @State private var query = ""
    @State private var showSettings = false

    private var filtered: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? lock.items : lock.items.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsView(lock: lock, back: { showSettings = false })
            } else {
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .onChange(of: query) { _, _ in lock.touch() }

                // thin bar that shrinks as the 60s window runs out
                GeometryReader { g in
                    Rectangle().fill(Color.accentColor.opacity(0.6))
                        .frame(width: g.size.width * CGFloat(lock.secondsLeft) / CGFloat(LockManager.unlockSeconds))
                }
                .frame(height: 2)

                if filtered.isEmpty {
                    Text(lock.items.isEmpty ? "Nothing copied yet" : "No matches")
                        .font(.system(size: 12)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { item in
                                ClipRow(item: item) {
                                    watcher.copyToPasteboard(item.text)
                                    lock.touch()
                                    NSApp.keyWindow?.close()
                                } onDelete: { lock.delete(item) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 360)
                }

                Divider()
                HStack(spacing: 14) {
                    IconButton("gearshape", "Settings") { showSettings = true; lock.touch() }
                    IconButton("trash", "Clear all") { lock.clearAll() }.disabled(lock.items.isEmpty)
                    Spacer()
                    IconButton("lock", "Lock now") { lock.lock() }
                    IconButton("power", "Quit") { NSApp.terminate(nil) }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
            }
        }
        .frame(width: panelWidth)
    }
}

struct ClipRow: View {
    let item: ClipItem
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Text(item.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces))
                .lineLimit(1).truncationMode(.tail)
                .font(.system(size: 12.5))
            Spacer(minLength: 0)
            if hover {
                Button(action: onDelete) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 5).fill(hover ? Color.primary.opacity(0.08) : .clear).padding(.horizontal, 4))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: onSelect)
    }
}

struct IconButton: View {
    let symbol: String, tip: String, action: () -> Void
    init(_ symbol: String, _ tip: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.tip = tip; self.action = action
    }
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12)) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help(tip)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var lock: LockManager
    let back: () -> Void
    @AppStorage("maxItems") private var maxItems = 100
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var oldPin = ""
    @State private var newPin = ""
    @State private var pinMsg = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconButton("chevron.left", "Back", action: back)
                Text("Settings").font(.headline)
            }
            Stepper("Keep \(maxItems) items", value: $maxItems, in: 10...1000, step: 10)
            Toggle("Launch at login", isOn: $launchAtLogin).toggleStyle(.switch).controlSize(.small)
                .onChange(of: launchAtLogin) { _, on in
                    if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                }
            Divider()
            SecureField("Current PIN", text: $oldPin).textFieldStyle(.roundedBorder)
            SecureField("New PIN", text: $newPin).textFieldStyle(.roundedBorder)
            HStack {
                Text(pinMsg).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Change PIN") {
                    pinMsg = lock.changePIN(old: oldPin, new: newPin) ? "Changed" : (lock.lastError ?? "Failed")
                    oldPin = ""; newPin = ""
                }.controlSize(.small).disabled(newPin.count < 6 || oldPin.isEmpty)
            }
            Divider()
            Button("Reset vault", role: .destructive) { lock.reset() }.controlSize(.small)
        }
        .font(.system(size: 12))
        .padding(14)
    }
}
