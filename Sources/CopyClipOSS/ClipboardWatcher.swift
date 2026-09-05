import AppKit

/// Polls the system pasteboard. Text only (like CopyClip).
/// Skips items flagged as concealed by password managers.
@MainActor
final class ClipboardWatcher {
    private let pb = NSPasteboard.general
    private var lastCount: Int
    private var timer: Timer?
    private let onCopy: (String, String?) -> Void
    static let maxBytes = 512 * 1024

    init(onCopy: @escaping (String, String?) -> Void) {
        self.onCopy = onCopy
        lastCount = pb.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        let types = pb.types ?? []
        // http://nspasteboard.org conventions
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) { return }
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) { return }
        if let mark = pb.string(forType: NSPasteboard.PasteboardType("com.copycliposs.self")), mark == "1" { return }
        guard let s = pb.string(forType: .string), !s.isEmpty, s.utf8.count <= Self.maxBytes else { return }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName
        onCopy(s, app)
    }

    /// Put text back on the clipboard without re-recording it.
    func copyToPasteboard(_ text: String) {
        pb.clearContents()
        pb.setString(text, forType: .string)
        pb.setString("1", forType: NSPasteboard.PasteboardType("com.copycliposs.self"))
        lastCount = pb.changeCount
    }
}
