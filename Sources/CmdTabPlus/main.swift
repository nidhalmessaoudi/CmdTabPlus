import AppKit
import ServiceManagement
import ApplicationServices
import SwitchingCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let switcher = KeyboardSwitcher()
    private var status: NSStatusItem!
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var permissionWindow: NSWindow?
    private var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
    private var failure = false
    private var previousTrust = AXIsProcessTrusted()
    private var visualCheckPanel: SwitcherPanel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--visual-check") {
            // Developer-only fixture: render the actual panel without installing a tap
            // or reading another application's windows. Exits automatically.
            let app = NSRunningApplication.current
            let element = AXUIElementCreateApplication(getpid())
            let entries = [AppEntry(app: app, name: "CmdTabPlus", windows: []),
                           AppEntry(app: app, name: "Safari", windows: [
                            WindowEntry(element: element, title: "A quieter way to switch", minimized: false),
                            WindowEntry(element: element, title: "Design notes — CmdTabPlus", minimized: false),
                            WindowEntry(element: element, title: "Weekend reading", minimized: true)])]
            let preview = SwitcherPanel(); visualCheckPanel = preview
            let selection = SwitchingSession(windowCounts: [0, 3])!
            preview.show(entries, selection)
            if let flag = CommandLine.arguments.firstIndex(of: "--animation-check"),
               CommandLine.arguments.indices.contains(flag + 1) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    preview.checkAnimations(apps: entries, expanded: selection,
                        output: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) { NSApp.terminate(nil) }
            return
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "app.cmdtabplus").count <= 1 else { NSApp.terminate(nil); return }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "CmdTabPlus")
        status.button?.toolTip = "CmdTabPlus — the app switcher, with windows"
        switcher.onFailure = { [weak self] in self?.failure = true; self?.updateMenu() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.switcher.catalog.activated(app.processIdentifier)
            self.switcher.catalog.refresh()
        })
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.switcher.cancel() })
        }
        if let front = NSWorkspace.shared.frontmostApplication { switcher.catalog.activated(front.processIdentifier) }
        if enabled && AXIsProcessTrusted() { failure = !switcher.start() }
        updateMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AXIsProcessTrusted()
            if trusted != self.previousTrust {
                self.previousTrust = trusted
                self.failure = false
                if !trusted { self.switcher.stop() }
                self.updateMenu()
            }
            self.switcher.healthCheck()
            if self.enabled && AXIsProcessTrusted() {
                if !self.failure && !self.switcher.running { self.failure = !self.switcher.start(); self.updateMenu() }
                self.switcher.catalog.refresh()
            }
            self.writeDiagnostics()
        }
        if !UserDefaults.standard.bool(forKey: "introduced") { showPermissions(); UserDefaults.standard.set(true, forKey: "introduced") }
    }
    private func writeDiagnostics() {
        guard let flag = CommandLine.arguments.firstIndex(of: "--diagnostics"),
              CommandLine.arguments.indices.contains(flag + 1) else { return }
        // Opt-in local support output: aggregate state only, never titles or keys.
        let data: [String: Any] = [
            "accessibilityTrusted": AXIsProcessTrusted(), "enabled": enabled,
            "tapRunning": switcher.running, "paused": failure,
            "apps": switcher.catalog.entries.count,
            "windows": switcher.catalog.entries.reduce(0) { $0 + $1.windows.count },
            "scanBusy": switcher.catalog.busy, "scanSeconds": switcher.catalog.scanDuration,
            "snapshotAge": Date().timeIntervalSince(switcher.catalog.updated),
            "commandTabEvents": switcher.commandTabEvents,
            "interceptedEvents": switcher.interceptedEvents,
            "lastPassReason": switcher.lastPassReason,
            "bundlePath": Bundle.main.bundlePath
        ]
        if let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]), options: .atomic)
        }
    }
    func menuWillOpen(_ menu: NSMenu) { updateMenu() }
    private func updateMenu() {
        let menu = status.menu ?? NSMenu(); menu.removeAllItems(); menu.delegate = self
        let state = !enabled ? "Disabled" : !AXIsProcessTrusted() ? "Accessibility permission needed" : failure ? "Paused — native switching available" : switcher.catalog.entries.isEmpty ? "Discovering applications…" : "Ready — \(switcher.catalog.entries.count) apps"
        menu.addItem(withTitle: state, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let toggle = menu.addItem(withTitle: "Enable CmdTabPlus", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.state = enabled ? .on : .off
        if failure { menu.addItem(withTitle: "Retry Enhanced Switching", action: #selector(retry), keyEquivalent: "") }
        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if SMAppService.mainApp.status == .requiresApproval { menu.addItem(withTitle: "Approve in Login Items…", action: #selector(loginSettings), keyEquivalent: "") }
        menu.addItem(withTitle: "Accessibility Permission…", action: #selector(showPermissions), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit CmdTabPlus", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        status.menu = menu
    }
    @objc private func toggleEnabled() {
        enabled.toggle(); UserDefaults.standard.set(enabled, forKey: "enabled")
        if enabled { retry(); if !AXIsProcessTrusted() { showPermissions() } } else { switcher.stop() }
        updateMenu()
    }
    @objc private func retry() { failure = AXIsProcessTrusted() ? !switcher.start() : false; switcher.catalog.refresh(); updateMenu() }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert(); alert.messageText = "Couldn’t change launch at login"
            alert.informativeText = "Keep CmdTabPlus in Applications and try again.\n\n\(error.localizedDescription)"; alert.runModal()
        }
        updateMenu()
    }
    @objc private func loginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func showPermissions() {
        if let permissionWindow { NSApp.activate(ignoringOtherApps: true); permissionWindow.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 310), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "CmdTabPlus"; window.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(wrappingLabelWithString: "The app switcher, with windows."); title.font = .systemFont(ofSize: 24, weight: .semibold)
        let text = NSTextField(wrappingLabelWithString: "Hold Command. Press Tab to move through apps and their windows. Release Command to switch.\n\nAllow Accessibility so CmdTabPlus can handle Command+Tab, read window titles, and focus your selected window. No screen recording. No titles saved or sent anywhere.\n\nWithout access, macOS switching stays available.")
        text.font = .systemFont(ofSize: 13); text.textColor = .secondaryLabelColor
        let button = NSButton(title: "Open Accessibility Settings…", target: self, action: #selector(openAccessibility)); button.bezelStyle = .rounded
        stack.addArrangedSubview(title); stack.addArrangedSubview(text); stack.addArrangedSubview(button)
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 26)])
        permissionWindow = window; window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    @objc private func openAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func quit() { switcher.stop(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { switcher.stop(); timer?.invalidate() }
}
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
