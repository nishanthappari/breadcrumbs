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

/// Global shortcuts that answer a pending check-in from any app. Registered only while a
/// check-in is waiting, so they never shadow those keys in other apps the rest of the time.
enum CheckInShortcut {
    static let yes = "⌃⇧Y"
    static let no = "⌃⇧N"
    /// Last box only: tick it and stop (⌃⇧Y rolls into the next sprint there).
    static let stop = "⌃⇧S"
}

/// A system-wide shortcut via Carbon's RegisterEventHotKey (no Accessibility permission needed).
/// Several can coexist: each gets its own EventHotKeyID, and one shared app-level handler
/// routes a press to the instance whose id fired. Unregistered when the instance is released.
/// Main thread only.
final class HotKey {
    static let displayString = "⌃⇧B"

    private static let signature = OSType(0x4252_4443) // 'BRDC'
    private static var nextID: UInt32 = 1
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false

    let display: String
    private let id: UInt32
    private var ref: EventHotKeyRef?
    private(set) var isRegistered = false

    init(keyCode: Int = kVK_ANSI_B, modifiers: Int = controlKey | shiftKey,
         display: String = HotKey.displayString, action: @escaping () -> Void) {
        self.display = display
        id = Self.nextID
        Self.nextID += 1
        guard Self.installHandler() else { return }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        isRegistered = status == noErr
        if isRegistered {
            Self.actions[id] = action
        } else {
            ref = nil
            NSLog("Breadcrumbs: hotkey \(display) registration failed (\(status)), likely taken by another app")
        }
    }

    /// Releases the shortcut so other apps get the keystroke again.
    func unregister() {
        Self.actions[id] = nil
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        isRegistered = false
    }

    deinit { unregister() }

    /// Installs the one shared handler (kept for the app's lifetime).
    private static func installHandler() -> Bool {
        if handlerInstalled { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hk = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard err == noErr, hk.signature == HotKey.signature else { return OSStatus(eventNotHandledErr) }
            let fired = hk.id
            // Run after the Carbon callback returns, so an action may unregister hotkeys safely.
            DispatchQueue.main.async { HotKey.actions[fired]?() }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = status == noErr
        if !handlerInstalled { NSLog("Breadcrumbs: hotkey handler install failed (\(status))") }
        return handlerInstalled
    }
}
