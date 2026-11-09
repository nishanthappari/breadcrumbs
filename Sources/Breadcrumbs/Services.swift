import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// The bundled soft chime.
@MainActor
final class Chime {
    private let sound: NSSound?

    init() {
        let url = Bundle.main.url(forResource: "chime", withExtension: "wav")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../Resources/chime.wav").standardized
        sound = NSSound(contentsOf: url, byReference: false)
        sound?.volume = 0.55
    }

    func play() {
        sound?.stop()
        sound?.play()
    }
}

/// Launch at login through SMAppService (macOS 13+).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .notRegistered: return "notRegistered"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown"
        }
    }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Breadcrumbs: login item \(on ? "register" : "unregister") failed: \(error)")
        }
    }

    /// Registers once on the first launch from an installed location; respects a later opt-out.
    static func registerOnFirstInstalledLaunch() {
        let key = "loginItemConfigured"
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app"), !path.contains("/.build/"),
              !UserDefaults.standard.bool(forKey: key) else { return }
        if SMAppService.mainApp.status != .enabled { set(true) }
        UserDefaults.standard.set(true, forKey: key)
    }
}

/// A system-wide shortcut via Carbon's RegisterEventHotKey (no Accessibility permission needed).
final class HotKey {
    static let displayString = "⌃⌥B"

    private var ref: EventHotKeyRef?
    private(set) var isRegistered = false
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: Int = kVK_ANSI_B, modifiers: Int = controlKey | optionKey, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4252_4443), id: 1) // 'BRDC'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
        isRegistered = status == noErr
        if !isRegistered { NSLog("Breadcrumbs: hotkey registration failed (\(status))") }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
