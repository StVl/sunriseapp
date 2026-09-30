import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let state = AppState()
    private var window: NSWindow!
    private var cancellables = Set<AnyCancellable>()
    /// True when we entered full screen for ringing, so Stop/Snooze can leave it again.
    private var autoFullScreen = false
    private var sigterm: DispatchSourceSignal?
    private var backlightTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        // SPEC §2: transparent titlebar, content runs under it.
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.title = "Sunrise"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.backgroundColor = NSColor(srgbRed: 0x1a / 255, green: 0x0c / 255, blue: 0x05 / 255, alpha: 1)
        w.minSize = NSSize(width: 760, height: 700)
        w.isReleasedWhenClosed = false
        w.collectionBehavior.insert(.fullScreenPrimary)
        w.contentView = NSHostingView(rootView: RootView().environmentObject(state).environmentObject(state.license))
        w.delegate = self
        w.center()
        w.setFrameAutosaveName("SunriseMain")
        window = w

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        state.$phase
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] in self?.phaseChanged($0) }
            .store(in: &cancellables)

        // Backlight runs on its own clock, not the lamp's render loop: rendering stops when the
        // window is hidden, and the screen must still be handed back then.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.driveBacklight() }
        }
        RunLoop.main.add(timer, forMode: .common)
        backlightTimer = timer

        // A kill (pkill, logout) must still hand the backlight back.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigterm = source

        // Dev shortcut: `open build/Sunrise.app --args --ring-now` rings with demo timings.
        if CommandLine.arguments.contains("--ring-now") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.state.ring(quick: true)
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.tick() }
        }

        // Spotify brings itself forward when it launches or starts playing. During the sunrise the
        // light is the alarm, so send it back and keep the lamp on screen.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, self.state.phase == .ringing, app?.bundleIdentifier == Spotify.bundleID else { return }
                app?.hide()
                self.showWindow()
            }
        }
    }

    // The alarm must keep working with the window closed: closing only hides it.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Backlight.shared.restore()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var isFullScreen: Bool { window.styleMask.contains(.fullScreen) }

    /// Ringing: wake the display and take over the screen (SPEC §12).
    private func phaseChanged(_ phase: Phase) {
        if phase == .ringing {
            KeepAwake.wakeDisplay()
            showWindow()
            if !isFullScreen {
                autoFullScreen = true
                window.toggleFullScreen(nil)
            }
        } else if autoFullScreen {
            autoFullScreen = false
            if isFullScreen { window.toggleFullScreen(nil) }
        }
    }

    // MARK: - Backlight

    private func driveBacklight() {
        let now = Date()
        let b = Float(min(max(1 - state.overlayOpacity(at: now), 0), 1))
        let night = Backlight.nightLevel
        // Only while Sunrise is what's on screen: never dim the display under someone's work.
        let inFront = NSApp.isActive && window.isVisible && window.occlusionState.contains(.visible)
        let target: ((Float) -> Float)?
        switch state.phase {
        case .armed:
            target = state.dimAtNight && inFront ? { _ in night } : nil
        case .ringing:
            // From the night floor (or the user's level) up to 100% (or back to the user's level).
            let dim = state.dimAtNight, boost = state.hdrBoost
            target = { saved in
                let from = dim ? night : saved
                let to = boost ? 1 : saved
                return from + (to - from) * b
            }
        case .editing:
            target = state.previewStart != nil && state.hdrBoost ? { saved in saved + (1 - saved) * b } : nil
        }
        // Ringing re-asserts the level: auto-brightness would otherwise pull it down in a dark room.
        Backlight.shared.drive(target, insist: state.phase == .ringing, now: now)
    }

    // MARK: - Menu

    private func buildMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Sunrise", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "License…", action: #selector(showLicense), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Sunrise", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Sunrise", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "Sunrise")

        // Text fields get ⌘X/⌘C/⌘V/⌘A only through these menu items.
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: editMenu, title: "Edit")

        let viewMenu = NSMenu(title: "View")
        for name in LavaPalette.Name.allCases {
            let item = viewMenu.addItem(withTitle: "\(name.rawValue) Palette", action: #selector(selectPalette(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name.rawValue
        }
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Max Brightness at Sunrise", action: #selector(toggleHDR), keyEquivalent: "").target = self
        viewMenu.addItem(withTitle: "Dim Screen While Armed", action: #selector(toggleNight), keyEquivalent: "").target = self
        viewMenu.addItem(.separator())
        let fullScreen = viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        main.addItem(submenu: viewMenu, title: "View")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Show Sunrise", action: #selector(showWindowAction), keyEquivalent: "0").target = self
        main.addItem(submenu: windowMenu, title: "Window")
        NSApp.windowsMenu = windowMenu

        let debugMenu = NSMenu(title: "Debug")
        debugMenu.addItem(withTitle: "Ring Now (10 s sunrise)", action: #selector(ringNow), keyEquivalent: "r").target = self
        debugMenu.addItem(withTitle: "Demo Timings (10 s sunrise, 5 s snooze)", action: #selector(toggleDemo), keyEquivalent: "").target = self
        debugMenu.addItem(.separator())
        debugMenu.addItem(withTitle: "Expire Trial", action: #selector(debugExpireTrial), keyEquivalent: "").target = self
        debugMenu.addItem(withTitle: "Reset License & Trial", action: #selector(debugResetLicense), keyEquivalent: "").target = self
        main.addItem(submenu: debugMenu, title: "Debug")

        NSApp.mainMenu = main
    }

    @objc private func selectPalette(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let name = LavaPalette.Name(rawValue: raw) else { return }
        state.palette = name
    }

    @objc private func showWindowAction() { showWindow() }
    @objc private func ringNow() { state.ring(quick: true) }
    @objc private func toggleDemo() { state.demoTimings.toggle() }
    @objc private func toggleHDR() { state.hdrBoost.toggle() }
    @objc private func debugExpireTrial() { state.license.debugExpireTrial() }
    @objc private func debugResetLicense() { state.license.debugReset() }
    @objc private func showLicense() {
        showWindow()
        state.showLicensePanel = true
    }
    @objc private func toggleNight() { state.dimAtNight.toggle() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(selectPalette(_:)):
            item.state = (item.representedObject as? String) == state.palette.rawValue ? .on : .off
        case #selector(toggleDemo):
            item.state = state.demoTimings ? .on : .off
        case #selector(toggleHDR):
            item.state = state.hdrBoost ? .on : .off
        case #selector(toggleNight):
            item.state = state.dimAtNight ? .on : .off
        case #selector(ringNow):
            return state.phase != .ringing
        default:
            break
        }
        return true
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
