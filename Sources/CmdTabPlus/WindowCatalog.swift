import AppKit
import ApplicationServices

struct WindowEntry {
    let element: AXUIElement
    let title: String
    let minimized: Bool
}
struct AppEntry {
    let app: NSRunningApplication
    let name: String
    let windows: [WindowEntry]
}
func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
}
final class WindowCatalog {
    private let queue = DispatchQueue(label: "app.cmdtabplus.accessibility", qos: .userInitiated)
    private(set) var busy = false
    private(set) var scanDuration: TimeInterval = 0
    private(set) var entries: [AppEntry] = []
    private(set) var updated = Date.distantPast
    private var recent: [pid_t] = []
    func activated(_ pid: pid_t) {
        recent.removeAll { $0 == pid }; recent.insert(pid, at: 0)
    }
    func refresh() {
        guard !busy, AXIsProcessTrusted() else { return }
        busy = true
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() && !$0.isTerminated }
        let order = recent
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        queue.async {
            AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.08)
            let start = Date()
            var result: [AppEntry] = []
            for app in apps {
                // A slow app must not prevent every other app from switching.
                // Keep all running apps in the ring; unavailable windows fall back
                // to ordinary app activation rather than discarding the snapshot.
                guard Date().timeIntervalSince(start) < 1.2 else {
                    result.append(AppEntry(app: app, name: app.localizedName ?? "Application", windows: []))
                    continue
                }
                let ax = AXUIElementCreateApplication(app.processIdentifier)
                var windows = (attribute(ax, kAXWindowsAttribute) as? [AXUIElement] ?? []).compactMap { element -> WindowEntry? in
                    guard Date().timeIntervalSince(start) < 1.2 else { return nil }
                    let role = attribute(element, kAXRoleAttribute) as? String
                    let subrole = attribute(element, kAXSubroleAttribute) as? String
                    guard role == kAXWindowRole, subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { return nil }
                    let title = (attribute(element, kAXTitleAttribute) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return WindowEntry(element: element, title: title?.isEmpty == false ? title! : "Untitled window", minimized: (attribute(element, kAXMinimizedAttribute) as? Bool) == true)
                }
                // AXWindows ordering is app-defined, so explicitly anchor the
                // ring at the focused window rather than assuming it is first.
                if let focused = attribute(ax, kAXFocusedWindowAttribute),
                   let index = windows.firstIndex(where: { CFEqual($0.element, focused) }), index != 0 {
                    windows.insert(windows.remove(at: index), at: 0)
                }
                result.append(AppEntry(app: app, name: app.localizedName ?? "Application", windows: windows))
            }
            let duration = Date().timeIntervalSince(start)
            result.sort { a, b in
                func rank(_ pid: pid_t) -> Int { pid == front ? -1 : (order.firstIndex(of: pid) ?? Int.max) }
                let l = rank(a.app.processIdentifier), r = rank(b.app.processIdentifier)
                return l == r ? a.name.localizedStandardCompare(b.name) == .orderedAscending : l < r
            }
            let snapshot = result
            DispatchQueue.main.async {
                self.busy = false
                self.entries = snapshot; self.updated = Date(); self.scanDuration = duration
            }
        }
    }
    func activate(_ entry: AppEntry, window: Int) {
        guard !entry.app.isTerminated else { return }
        entry.app.unhide()
        entry.app.activate(options: [.activateIgnoringOtherApps])
        guard entry.windows.indices.contains(window), AXIsProcessTrusted() else { return }
        let target = entry.windows[window].element
        queue.async {
            AXUIElementSetMessagingTimeout(target, 0.15)
            AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(target, kAXRaiseAction as CFString)
            let app = AXUIElementCreateApplication(entry.app.processIdentifier)
            AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, target)
        }
    }
}
