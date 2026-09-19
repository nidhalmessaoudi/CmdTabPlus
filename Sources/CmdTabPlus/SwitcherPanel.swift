import AppKit
import SwiftUI
import SwitchingCore

private struct AppStrip: View {
    let apps: [AppEntry]
    let selected: Int
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(apps.indices, id: \.self) { index in
                        VStack(spacing: 8) {
                            Image(nsImage: apps[index].app.icon ?? NSImage(named: NSImage.applicationIconName)!)
                                .resizable().interpolation(.high).frame(width: 64, height: 64)
                            Text(apps[index].name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        }
                        .frame(width: 88, height: 104)
                        .background(index == selected ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 15))
                        .accessibilityElement(children: .ignore).accessibilityLabel(apps[index].name)
                        .accessibilityAddTraits(index == selected ? .isSelected : []).id(index)
                    }
                }.padding(16)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { proxy.scrollTo($0, anchor: .center) }
        }
    }
}

private struct WindowList: View {
    let entry: AppEntry
    let selected: Int
    var body: some View {
        HStack(spacing: 0) {
            Divider().padding(.vertical, 22)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.name).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(selected + 1) of \(entry.windows.count)").font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.horizontal, 10)
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(entry.windows.indices, id: \.self) { index in
                                HStack(spacing: 10) {
                                    Image(systemName: entry.windows[index].minimized ? "minus.rectangle" : "macwindow")
                                        .foregroundStyle(.secondary)
                                    Text(entry.windows[index].title).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }.padding(.horizontal, 10).frame(height: 34)
                                .background(index == selected ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityAddTraits(index == selected ? .isSelected : []).id(index)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(selected, anchor: .center) }
                    .onChange(of: selected) { proxy.scrollTo($0, anchor: .center) }
                }.id(entry.app.processIdentifier)
            }.padding(16)
        }
    }
}

final class SwitcherPanel {
    private let panel: NSPanel
    private let stage = NSView()
    private let canvas = NSView()
    private var surface: NSView?
    private var appsView: NSHostingView<AppStrip>?
    private var windowsView: NSHostingView<WindowList>?
    private var materialMode: Int?
    private var gestureID: Int?
    private var lastAnnouncement: String?
    private var transitionID = 0
    private var targetFrame = NSRect.zero
    private var targetExpanded = false
    private var dismissing = false
    private var activeVisibleFrame: NSRect?
    private let height: CGFloat = 176
    private let extensionWidth: CGFloat = 301
    private let padding: CGFloat = 24

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false // The native glass surface supplies its own depth.
        panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none
        panel.setAccessibilityLabel("CmdTabPlus app switcher")
        stage.wantsLayer = true
        canvas.wantsLayer = true
        canvas.layer?.masksToBounds = true
        panel.contentView = stage
    }

    private func configureSurface() {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let mode: Int
        if #available(macOS 26.0, *) { mode = reduceTransparency ? 0 : 2 }
        else { mode = reduceTransparency ? 0 : 1 }
        guard materialMode != mode else { return }
        surface?.removeFromSuperview(); canvas.removeFromSuperview()
        let material: NSView
        if #available(macOS 26.0, *), mode == 2 {
            let glass = NSGlassEffectView()
            glass.style = .clear; glass.tintColor = nil; glass.cornerRadius = 26
            glass.contentView = canvas
            material = glass
        } else {
            let fallback = NSVisualEffectView()
            fallback.material = .hudWindow; fallback.blendingMode = .behindWindow; fallback.state = .active
            fallback.wantsLayer = true; fallback.layer?.cornerRadius = 26; fallback.layer?.masksToBounds = true
            if reduceTransparency { fallback.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
            canvas.autoresizingMask = [.width, .height]
            fallback.addSubview(canvas)
            material = fallback
        }
        material.wantsLayer = true
        stage.addSubview(material)
        surface = material; materialMode = mode
    }

    func show(_ apps: [AppEntry], _ session: SwitchingSession, gesture: Int = 0) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let fresh = gestureID != gesture || !panel.isVisible
        if fresh { activeVisibleFrame = screen.visibleFrame }
        let available = activeVisibleFrame ?? screen.visibleFrame
        let wasDismissing = dismissing
        dismissing = false
        transitionID += 1
        let mainWidth = min(CGFloat(apps.count) * 96 + 24, max(120, available.width - extensionWidth - 2 * padding))
        let expanded = apps[session.app].windows.count > 1
        let fullWidth = mainWidth + extensionWidth + 2 * padding
        configureSurface()
        guard let surface else { return }

        // The WindowServer surface stays fixed throughout a gesture. Only the
        // layer-backed glass view animates, so no live NSWindow resize/repainting.
        if fresh {
            transitionID += 1
            surface.layer?.removeAllAnimations()
            windowsView?.layer?.removeAllAnimations()
            gestureID = gesture
            panel.setFrame(NSRect(x: available.midX - fullWidth / 2, y: available.midY - (height + 2 * padding) / 2,
                                  width: fullWidth, height: height + 2 * padding), display: false)
        }
        let appRoot = AppStrip(apps: apps, selected: session.app)
        if let appsView { appsView.rootView = appRoot }
        else {
            let host = NSHostingView(rootView: appRoot); host.sizingOptions = []; host.wantsLayer = true
            canvas.addSubview(host); appsView = host
        }
        appsView?.frame = NSRect(x: 0, y: 0, width: mainWidth, height: height)
        if expanded {
            let root = WindowList(entry: apps[session.app], selected: session.window)
            if let windowsView { windowsView.rootView = root }
            else {
                let host = NSHostingView(rootView: root); host.sizingOptions = []; host.wantsLayer = true
                canvas.addSubview(host); windowsView = host
            }
        }
        windowsView?.frame = NSRect(x: mainWidth, y: 0, width: extensionWidth, height: height)
        // Constant height avoids text relayout/vertical bouncing. Long lists scroll.
        let width = mainWidth + (expanded ? extensionWidth : 0)
        let frame = NSRect(x: (stage.bounds.width - width) / 2, y: padding, width: width, height: height)
        let needsTransition = frame != targetFrame || expanded != targetExpanded || surface.alphaValue != 1 || wasDismissing
        targetFrame = frame; targetExpanded = expanded
        if fresh || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            transitionID += 1
            surface.layer?.removeAllAnimations(); windowsView?.layer?.removeAllAnimations()
            surface.frame = frame; surface.alphaValue = 1
            windowsView?.alphaValue = expanded ? 1 : 0
        } else if needsTransition {
            transitionID += 1
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                surface.animator().frame = frame
                surface.animator().alphaValue = 1
                windowsView?.animator().alphaValue = expanded ? 1 : 0
            }
        }
        // No teardown completion: the right-side view remains mounted, clipped and
        // faded out. Rapid reversals cannot run a stale removal/reopen callback.
        if !panel.isVisible { panel.orderFrontRegardless() }
        let entry = apps[session.app]
        let title = entry.windows.indices.contains(session.window) ? entry.windows[session.window].title : entry.name
        let announcement = "\(entry.name), \(title)"
        if lastAnnouncement != announcement {
            lastAnnouncement = announcement
            NSAccessibility.post(element: panel, notification: .announcementRequested,
                                 userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    func hide() {
        guard panel.isVisible, let surface else { return }
        transitionID += 1
        let token = transitionID
        dismissing = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.08
            surface.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.transitionID == token else { return }
            self.panel.orderOut(nil); self.gestureID = nil; self.lastAnnouncement = nil
        }
    }

    // Developer fixture checks presentation-layer geometry, not just target frames.
    func checkAnimations(apps: [AppEntry], expanded: SwitchingSession, output: URL) {
        guard apps.contains(where: { $0.windows.count <= 1 }), let surface else { return }
        let outerFrame = panel.frame
        let expandedWidth = surface.frame.width
        var collapsed = expanded
        while apps[collapsed.app].windows.count > 1 { collapsed.advance() }
        let selection = collapsed
        var lastWidth = expandedWidth
        var monotonic = true, centered = true, stableWindow = true
        var intermediateFrames = 0
        show(apps, selection)
        let sampler = Timer(timeInterval: 0.008, repeats: true) { [self] _ in
            let frame = surface.layer?.presentation()?.frame ?? surface.frame
            if frame.width < expandedWidth - 1 && frame.width > expandedWidth - extensionWidth + 1 { intermediateFrames += 1 }
            monotonic = monotonic && frame.width <= lastWidth + 0.5
            centered = centered && abs(frame.midX - stage.bounds.midX) < 1
            stableWindow = stableWindow && panel.frame == outerFrame
            lastWidth = frame.width
        }
        RunLoop.main.add(sampler, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in
            sampler.invalidate()
            let collapsedWidth = surface.frame.width
            let correct = abs(expandedWidth - collapsedWidth - extensionWidth) < 1
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [self] in show(apps, expanded) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in
                let survives = panel.isVisible && surface.alphaValue == 1
                show(apps, selection)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [self] in show(apps, expanded) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in show(apps, selection) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                    let results = ["collapseIsMonotonic": monotonic, "collapsedWidthCorrect": correct,
                                   "staysCenteredDuringTransition": centered, "outerWindowNeverResizes": stableWindow,
                                   "rendersIntermediateFrames": intermediateFrames > 1 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                                   "reopenSurvivesOldDismissal": survives,
                                   "rapidRetargetSettles": panel.isVisible && abs(surface.frame.width - collapsedWidth) < 1]
                    if let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]) {
                        try? data.write(to: output, options: .atomic)
                    }
                    show(apps, expanded)
                }
            }
        }
    }
}
