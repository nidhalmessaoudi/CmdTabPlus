import AppKit
import ApplicationServices
import SwitchingCore

final class KeyboardSwitcher {
    let catalog = WindowCatalog()
    private let panel = SwitcherPanel()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var session: SwitchingSession?
    private var frozen: [AppEntry] = []
    private var swallowedTab = false
    private var lastInput = Date()
    private var generation = 0
    private var gesture = 0
    private(set) var commandTabEvents = 0
    private(set) var interceptedEvents = 0
    private(set) var lastPassReason = "None"
    var onFailure: (() -> Void)?
    var running: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    func start() -> Bool {
        if running { return true }
        stop()
        guard AXIsProcessTrusted() else { return false }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return Unmanaged<KeyboardSwitcher>.fromOpaque(info).takeUnretainedValue().handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return false }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return running
    }
    func stop() {
        cancel()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; swallowedTab = false
    }
    func cancel() {
        guard session != nil else { return }
        generation += 1; session = nil; frozen = []
        let token = generation
        DispatchQueue.main.async { if self.generation == token { self.panel.hide() } }
    }
    func healthCheck() {
        if session != nil {
            if !CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) { finish() }
            else if Date().timeIntervalSince(lastInput) > 30 { cancel() }
        }
        if tap != nil && (!AXIsProcessTrusted() || !running) { stop(); onFailure?() }
    }
    private func finish() {
        guard let session, frozen.indices.contains(session.app) else { return }
        let target = frozen[session.app]
        cancel()
        DispatchQueue.main.async { self.catalog.activate(target, window: session.window) }
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Never blindly re-enable a tap the system disabled. The menu offers retry.
            cancel()
            DispatchQueue.main.async { self.stop(); self.onFailure?() }
            return pass
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp && key == 48 && swallowedTab { swallowedTab = false; return nil }
        if type == .flagsChanged {
            if !event.flags.contains(.maskCommand) { finish() }
            return pass
        }
        if type == .leftMouseDown || type == .rightMouseDown { cancel(); return pass }
        guard type == .keyDown else { return pass }
        // Other chords remain native, including Shift+Command+Tab. Cancel before passing.
        let shouldHandle = ShortcutPolicy.handles(keyCode: key, command: event.flags.contains(.maskCommand),
            shift: event.flags.contains(.maskShift), control: event.flags.contains(.maskControl), option: event.flags.contains(.maskAlternate))
        guard shouldHandle else {
            if session != nil { cancel() }
            return pass
        }
        commandTabEvents += 1
        if session == nil {
            guard !NSScreen.screens.isEmpty, Date().timeIntervalSince(catalog.updated) < 2.5,
                  catalog.entries.count > 0,
                  let front = NSWorkspace.shared.frontmostApplication,
                  let current = catalog.entries.firstIndex(where: { $0.app.processIdentifier == front.processIdentifier }) else {
                lastPassReason = catalog.entries.isEmpty ? "No application snapshot" : Date().timeIntervalSince(catalog.updated) >= 2.5 ? "Stale application snapshot" : "Foreground app not in snapshot or no display"
                return pass
            }
            gesture += 1
            frozen = catalog.entries
            session = SwitchingSession(windowCounts: frozen.map { $0.windows.count }, currentApp: current)
        } else { session?.advance() }
        guard let session else { return pass }
        interceptedEvents += 1
        lastPassReason = "None"
        lastInput = Date(); swallowedTab = true
        generation += 1
        let token = generation
        DispatchQueue.main.async {
            guard self.generation == token, self.session != nil else { return }
            self.panel.show(self.frozen, session, gesture: self.gesture)
        }
        return nil
    }
}
