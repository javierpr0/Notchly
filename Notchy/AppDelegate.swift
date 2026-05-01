import AppKit
import Sparkle
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private lazy var panel: TerminalPanel = TerminalPanel(sessionStore: sessionStore)
    private var notchWindow: NotchWindow?
    private let sessionStore = SessionStore.shared
    private var updaterController: SPUStandardUpdaterController?
    private var hoverHideTimer: Timer?
    private var hoverGlobalMonitor: Any?
    private var hoverLocalMonitor: Any?
    private var hotkeyMonitor: Any?
    /// Whether the panel was opened via notch hover (vs status item click)
    private var panelOpenedViaHover = false
    private let hoverMargin: CGFloat = 15
    private let hoverHideDelay: TimeInterval = 0.06

    private var replaceNotch: Bool {
        get {
            if UserDefaults.standard.object(forKey: "replaceNotch") == nil { return true }
            return UserDefaults.standard.bool(forKey: "replaceNotch")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "replaceNotch")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopHoverTracking()
        sessionStore.saveSessions()
        UserDefaults.standard.synchronize()
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        syncSparkleLanguage()
        setupStatusItem()
        setupPanel()
        if replaceNotch {
            setupNotchWindow()
        }
        setupHotkey()
        setupUpdater()
        observeUpdaterWindows()
        FullDiskAccessChecker.promptIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCheckForUpdates),
            name: .NotchyCheckForUpdates,
            object: nil
        )
    }

    /// Sparkle's update / progress / installed-version windows are plain
    /// NSWindows at .normal level, so our floating TerminalPanel obscures
    /// them. Watch every NSWindow that becomes key and, if it's owned by
    /// Sparkle, raise it to a level above the panel and the notch pill.
    private func observeUpdaterWindows() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow,
                  Self.isSparkleWindow(window) else { return }
            // .popUpMenu (101) is above .floating (3), .statusBar (25), and
            // .modalPanel (8) — guarantees the update prompt is reachable
            // even with the notch + panel both showing.
            window.level = .popUpMenu
            window.collectionBehavior.insert(.moveToActiveSpace)
            self?.notchWindow?.endHover()
        }
    }

    private static func isSparkleWindow(_ window: NSWindow) -> Bool {
        let className = String(describing: type(of: window))
        if className.hasPrefix("SU") || className.contains("Sparkle") { return true }
        if let delegate = window.delegate {
            let delegateClass = String(describing: type(of: delegate))
            if delegateClass.hasPrefix("SU") || delegateClass.contains("Sparkle") { return true }
        }
        return false
    }

    @objc private func handleCheckForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    private func syncSparkleLanguage() {
        let lang = L10n.shared.language.rawValue
        UserDefaults.standard.set([lang], forKey: "AppleLanguages")
    }

    private func setupUpdater() {
        do {
            let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
            try controller.updater.start()
            updaterController = controller
        } catch {
            NSLog("Sparkle updater failed to start: \(error)")
        }
    }

    private func setupStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(named: "menuIcon") //NSImage(systemSymbolName: "terminal", accessibilityDescription: "Notchy")
            button.image?.isTemplate = true  // lets macOS handle light/dark mode
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setupPanel() {
        // When the panel hides for any reason, clean up hover tracking
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.panel.isVisible else { return }
            self.notchWindow?.endHover()
            self.panelOpenedViaHover = false
            self.stopHoverTracking()
        }
        // When panel becomes key (user clicked on it), stop hover tracking
        // since resign-key will handle hiding from here
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.panelOpenedViaHover {
                self.panelOpenedViaHover = false
                self.stopHoverTracking()
            }
        }
    }

    private func setupNotchWindow() {
        notchWindow = NotchWindow { [weak self] in
            self?.notchHovered()
        }
        notchWindow?.isPanelVisible = { [weak self] in
            self?.panel.isVisible ?? false
        }
    }

    private func setupHotkey() {
        // Global monitor: fires when another app is focused (backtick = keyCode 50)
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 50,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.function).isEmpty
            else { return }
            DispatchQueue.main.async { self?.togglePanel() }
        }
    }

    private func notchHovered() {
        guard !panel.isVisible else { return }
        showPanelBelowNotch()
        panelOpenedViaHover = true
        startHoverTracking()
    }

    private func showPanelBelowNotch() {
        guard let screen = NSScreen.builtIn else { return }
        panel.showPanelCentered(on: screen)
    }

    // MARK: - Hover-to-hide tracking

    private func startHoverTracking() {
        stopHoverTracking()
        hoverGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.checkHoverBounds()
        }
        hoverLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.checkHoverBounds()
            return event
        }
    }

    private func stopHoverTracking() {
        hoverHideTimer?.invalidate()
        hoverHideTimer = nil
        if let monitor = hoverGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            hoverGlobalMonitor = nil
        }
        if let monitor = hoverLocalMonitor {
            NSEvent.removeMonitor(monitor)
            hoverLocalMonitor = nil
        }
    }

    private func checkHoverBounds() {
        guard panel.isVisible, panelOpenedViaHover, !sessionStore.isPinned, !sessionStore.isShowingDialog else {
            cancelHoverHide()
            return
        }

        let mouse = NSEvent.mouseLocation
        let inNotch = notchWindow?.frame.insetBy(dx: -hoverMargin, dy: -hoverMargin).contains(mouse) ?? false
        let inPanel = panel.frame.insetBy(dx: -hoverMargin, dy: -hoverMargin).contains(mouse)

        if inNotch || inPanel {
            cancelHoverHide()
        } else {
            scheduleHoverHide()
        }
    }

    private func scheduleHoverHide() {
        guard hoverHideTimer == nil else { return }
        hoverHideTimer = Timer.scheduledTimer(withTimeInterval: hoverHideDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            // Re-check one more time before hiding (mouse may have returned)
            let mouse = NSEvent.mouseLocation
            let inNotch = self.notchWindow?.frame.insetBy(dx: -self.hoverMargin, dy: -self.hoverMargin).contains(mouse) ?? false
            let inPanel = self.panel.frame.insetBy(dx: -self.hoverMargin, dy: -self.hoverMargin).contains(mouse)
            if !inNotch && !inPanel && !self.sessionStore.isPinned && !self.sessionStore.isShowingDialog {
                self.panel.hidePanel()
                self.notchWindow?.endHover()
                self.panelOpenedViaHover = false
                self.stopHoverTracking()
            }
        }
    }

    private func cancelHoverHide() {
        hoverHideTimer?.invalidate()
        hoverHideTimer = nil
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        showContextMenu()
    }

    private func togglePanel() {
        if panel.isVisible {
            panel.hidePanel()
            notchWindow?.endHover()
            panelOpenedViaHover = false
            stopHoverTracking()
        } else {
            panelOpenedViaHover = false
            showPanelBelowStatusItem()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let notchItem = NSMenuItem(
            title: L10n.shared.showInNotch,
            action: #selector(toggleReplaceNotch),
            keyEquivalent: ""
        )
        notchItem.target = self
        notchItem.state = replaceNotch ? .on : .off
        menu.addItem(notchItem)

        menu.addItem(.separator())

        if !sessionStore.sessions.isEmpty {
            for session in sessionStore.sessions {
                let item = NSMenuItem(
                    title: session.projectName,
                    action: #selector(selectSession(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = session.id
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let newItem = NSMenuItem(
            title: L10n.shared.newSession,
            action: #selector(createNewSession),
            keyEquivalent: "n"
        )
        newItem.target = self
        menu.addItem(newItem)
        menu.addItem(.separator())

        // Checkpoint section
        let eligibleSessions = sessionStore.checkpointEligibleSessions
        if !eligibleSessions.isEmpty {
            menu.addItem(.separator())

            let headingItem = NSMenuItem(title: L10n.shared.checkpoint, action: nil, keyEquivalent: "")
            headingItem.isEnabled = false
            menu.addItem(headingItem)

            let saveItem = NSMenuItem(
                title: L10n.shared.save,
                action: nil,
                keyEquivalent: ""
            )
            let saveMenu = NSMenu()
            for session in eligibleSessions {
                let item = NSMenuItem(
                    title: session.projectName,
                    action: #selector(createCheckpoint(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = session.id
                if let dir = session.projectPath {
                    let projectDir = (dir as NSString).deletingLastPathComponent
                    item.isEnabled = CheckpointManager.shared.isGitRepo(in: projectDir)
                } else {
                    item.isEnabled = false
                }
                saveMenu.addItem(item)
            }
            saveItem.submenu = saveMenu
            menu.addItem(saveItem)

            let restoreItem = NSMenuItem(
                title: L10n.shared.restoreFrom,
                action: nil,
                keyEquivalent: ""
            )
            let restoreMenu = NSMenu()
            for session in eligibleSessions {
                guard let dir = session.projectPath else { continue }
                let projectDir = (dir as NSString).deletingLastPathComponent
                let hasCheckpoint = !CheckpointManager.shared.checkpoints(for: session.projectName, in: projectDir).isEmpty
                guard hasCheckpoint else { continue }
                let item = NSMenuItem(
                    title: session.projectName,
                    action: #selector(restoreLastCheckpoint(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = session.id
                restoreMenu.addItem(item)
            }
            if restoreMenu.items.count > 0 {
                restoreItem.submenu = restoreMenu
                menu.addItem(restoreItem)
            }
        }

        menu.addItem(.separator())

        let updateItem = NSMenuItem(
            title: L10n.shared.checkForUpdates,
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.isEnabled = updaterController?.updater.canCheckForUpdates ?? false
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.shared.quitNotchly,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func selectSession(_ sender: NSMenuItem) {
        guard let sessionId = sender.representedObject as? UUID else { return }
        sessionStore.selectSession(sessionId)
        showPanelBelowStatusItem()
    }

    @objc private func createCheckpoint(_ sender: NSMenuItem) {
        guard let sessionId = sender.representedObject as? UUID else { return }
        sessionStore.createCheckpoint(for: sessionId)
    }

    @objc private func restoreLastCheckpoint(_ sender: NSMenuItem) {
        guard let sessionId = sender.representedObject as? UUID,
              let session = sessionStore.sessions.first(where: { $0.id == sessionId }),
              let dir = session.projectPath else { return }
        let projectDir = (dir as NSString).deletingLastPathComponent
        guard let latest = CheckpointManager.shared.checkpoints(for: session.projectName, in: projectDir).first else { return }
        sessionStore.restoreCheckpoint(latest, for: sessionId)
    }

    @objc private func toggleReplaceNotch() {
        replaceNotch = !replaceNotch
        if replaceNotch {
            setupNotchWindow()
        } else {
            notchWindow?.orderOut(nil)
            notchWindow = nil
        }
    }

    @objc private func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    @objc private func createNewSession() {
        sessionStore.createQuickSession()
        showPanelBelowStatusItem()
    }

    private func showPanelBelowStatusItem() {
        if let button = statusItem.button,
           let window = button.window {
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = window.convertToScreen(buttonRect)
            panel.showPanel(below: screenRect)
        }
    }

}
