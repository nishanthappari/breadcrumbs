import AppKit
import BreadcrumbsCore
import SwiftUI

struct BreadcrumbsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: delegate.model, openHistory: { delegate.coordinator.showHistory() })
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(chime: Chime())
    lazy var coordinator = WindowCoordinator(model: model)
    lazy var router = URLRouter(model: model, coordinator: coordinator)
    private var hotKey: HotKey?

    func applicationWillFinishLaunching(_ notification: Notification) {
        installURLHandler()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = coordinator
        installURLHandler() // re-install in case SwiftUI replaced ours
        model.activate()
        LoginItem.registerOnFirstInstalledLaunch()
        model.setLaunchAtLogin(LoginItem.isEnabled) // refresh published state
        hotKey = HotKey { [weak self] in
            MainActor.assumeIsolated { self?.hotKeyPressed() }
        }
        model.hotKeyRegistered = hotKey?.isRegistered ?? false
        model.writeStatus()
    }

    private func hotKeyPressed() {
        if model.engine.isAwaitingCheckIn {
            coordinator.refocus()
        } else if !model.engine.isActive {
            model.startSprint()
        }
    }

    private func installURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: s) else { return }
        router.handle(url)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(router.handle)
    }
}

/// `breadcrumbs://` commands, used by Raycast and the test harness.
@MainActor
final class URLRouter {
    let model: AppModel
    let coordinator: WindowCoordinator

    init(model: AppModel, coordinator: WindowCoordinator) {
        self.model = model
        self.coordinator = coordinator
    }

    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "breadcrumbs" else { return }
        let command = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        var q: [String: String] = [:]
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.forEach { q[$0.name.lowercased()] = $0.value ?? "" }

        switch command {
        case "start":
            if model.engine.isAwaitingCheckIn { coordinator.refocus(); return }
            guard !model.engine.isActive else { return }
            // Test override: breadcrumbs://start?seconds=10&boxes=3 (this sprint only; settings untouched).
            var override: SprintConfig?
            if let sec = q["seconds"].flatMap(Double.init) {
                override = SprintConfig(intervalSeconds: sec, boxes: q["boxes"].flatMap(Int.init) ?? model.boxesPerSprint)
            } else if let b = q["boxes"].flatMap(Int.init) {
                override = SprintConfig(intervalSeconds: model.nextConfig.intervalSeconds, boxes: b)
            }
            model.startSprint(override: override)
        case "pause": model.pause()
        case "resume": model.resume()
        case "toggle", "pause-resume", "toggle-pause":
            if model.engine.isAwaitingCheckIn { coordinator.refocus() } else { model.togglePause() }
        case "cancel", "stop": model.cancel()
        case "today", "history": coordinator.showHistory()
        case "answer", "checkin":
            let v = (q["worked"] ?? q["answer"] ?? "").lowercased()
            model.answer(worked: ["yes", "y", "true", "1"].contains(v))
        case "done": coordinator.closeCompletion()
        case "settings":
            if let m = q["interval"].flatMap(Int.init) { model.setInterval(m) }
            if let b = q["boxes"].flatMap(Int.init) { model.setBoxes(b) }
            if q["reset"] != nil { model.resetSettings() }
            if let l = q["login"] { model.setLaunchAtLogin(["1", "true", "on", "yes"].contains(l.lowercased())) }
        case "status": model.writeStatus()
        case "quit": NSApp.terminate(nil)
        default: NSLog("Breadcrumbs: unknown command \(command)")
        }
    }
}
