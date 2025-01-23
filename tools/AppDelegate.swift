import SwiftUI
import KeyboardShortcuts
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static var sharedStatusItem: NSStatusItem?
    private var isServiceTriggered: Bool = false
    
    var statusBarItem: NSStatusItem! {
        get {
            if AppDelegate.sharedStatusItem == nil {
                AppDelegate.sharedStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                configureStatusBarItem()
            }
            return AppDelegate.sharedStatusItem
        }
        set {
            AppDelegate.sharedStatusItem = newValue
        }
    }
    
    let appState = AppState.shared
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private(set) var popupWindow: NSWindow?
    private var settingsHostingView: NSHostingView<SettingsView>?
    private var aboutHostingView: NSHostingView<AboutView>?
    private let windowAccessQueue = DispatchQueue(label: "com.example.writingtools.windowQueue")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self

        if CommandLine.arguments.contains("--reset") {
            DispatchQueue.main.async { [weak self] in
                self?.performRecoveryReset()
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.setupMenuBar()
            
            if self?.statusBarItem == nil {
                self?.recreateStatusBarItem()
            }
            
            if !UserDefaults.standard.bool(forKey: "has_completed_onboarding") {
                self?.showOnboarding()
            }
            
            self?.requestAccessibilityPermissions()
        }

        KeyboardShortcuts.onKeyUp(for: .showPopup) { [weak self] in
            self?.showPopup()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        WindowManager.shared.cleanupWindows()
    }

    private func recreateStatusBarItem() {
        AppDelegate.sharedStatusItem = nil
        _ = self.statusBarItem
    }

    private func configureStatusBarItem() {
        guard let button = statusBarItem?.button else { return }
        button.image = NSImage(systemSymbolName: "pencil.circle", accessibilityDescription: "Writing Tools")
    }

    private func setupMenuBar() {
        guard let statusBarItem = self.statusBarItem else {
            print("Failed to create status bar item")
            return
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "i"))
        menu.addItem(NSMenuItem(title: "Reset App", action: #selector(resetApp), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusBarItem.menu = menu
    }

    @objc private func resetApp() {
        WindowManager.shared.cleanupWindows()
        recreateStatusBarItem()
        setupMenuBar()

        let alert = NSAlert()
        alert.messageText = "App Reset Complete"
        alert.informativeText = "The app has been reset. If you're still experiencing issues, try restarting the app."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func performRecoveryReset() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        WindowManager.shared.cleanupWindows()
        recreateStatusBarItem()
        setupMenuBar()

        let alert = NSAlert()
        alert.messageText = "Recovery Complete"
        alert.informativeText = "The app has been reset to its default state."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func requestAccessibilityPermissions() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let alert = NSAlert()
            alert.messageText = "Accessibility Access Required"
            alert.informativeText = "Writing Tools needs accessibility access to detect text selection and simulate keyboard shortcuts. Please grant access in System Settings > Privacy & Security > Accessibility."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")

            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Writing Tools"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        let onboardingView = OnboardingView(appState: appState)
        let hostingView = NSHostingView(rootView: onboardingView)
        window.contentView = hostingView
        window.level = .floating

        WindowManager.shared.setOnboardingWindow(window, hostingView: hostingView)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func showSettings() {
        settingsWindow?.close()
        settingsWindow = nil
        settingsHostingView = nil

        settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        settingsWindow?.title = "Settings"
        settingsWindow?.center()
        settingsWindow?.isReleasedWhenClosed = false

        let settingsView = SettingsView(appState: appState, showOnlyApiSetup: false)
        settingsHostingView = NSHostingView(rootView: settingsView)
        settingsWindow?.contentView = settingsHostingView
        settingsWindow?.delegate = self

        if let window = settingsWindow {
            window.level = .floating
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    @objc private func showAbout() {
        aboutWindow?.close()
        aboutWindow = nil
        aboutHostingView = nil

        aboutWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        aboutWindow?.title = "About Writing Tools"
        aboutWindow?.center()
        aboutWindow?.isReleasedWhenClosed = false

        let aboutView = AboutView()
        aboutHostingView = NSHostingView(rootView: aboutView)
        aboutWindow?.contentView = aboutHostingView
        aboutWindow?.delegate = self

        if let window = aboutWindow {
            window.level = .floating
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func showPopup() {
        appState.activeProvider.cancel()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let currentFrontmostApp = NSWorkspace.shared.frontmostApplication {
                self.appState.previousApplication = currentFrontmostApp
            }

            self.closePopupWindow()

            let generalPasteboard = NSPasteboard.general
            
            // Get initial pasteboard content
            let oldContents = generalPasteboard.string(forType: .string)
            
            // Prioritized image types (in order of preference)
            let supportedImageTypes = [
                NSPasteboard.PasteboardType("public.png"),
                NSPasteboard.PasteboardType("public.jpeg"),
                NSPasteboard.PasteboardType("public.tiff"),
                NSPasteboard.PasteboardType("com.compuserve.gif"),
                NSPasteboard.PasteboardType("public.image")
            ]
            var foundImage: Data? = nil

            // Try to find the first available image in order of preference
            for type in supportedImageTypes {
                if let data = generalPasteboard.data(forType: type) {
                    foundImage = data
                    NSLog("Selected image type: \(type)")
                    break // Take only the first matching format
                }
            }

            // Clear and perform copy command
            generalPasteboard.clearContents()
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                let selectedText = generalPasteboard.string(forType: .string) ?? ""

                // Update app state with found image if any
                self.appState.selectedImages = foundImage.map { [$0] } ?? []

                generalPasteboard.clearContents()
                if let oldContents = oldContents {
                    generalPasteboard.setString(oldContents, forType: .string)
                }

                let window = PopupWindow(appState: self.appState)
                window.delegate = self

                self.appState.selectedText = selectedText
                self.popupWindow = window

                // Set appropriate window size based on content
                if !selectedText.isEmpty || !self.appState.selectedImages.isEmpty {
                    window.setContentSize(NSSize(width: 400, height: 400))
                } else {
                    window.setContentSize(NSSize(width: 400, height: 100))
                }

                window.positionNearMouse()
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    @objc func handleSelectedText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            appState.previousApplication = frontmostApp

            // Prioritized image types (in order of preference)
            let supportedImageTypes = [
                NSPasteboard.PasteboardType("public.png"),
                NSPasteboard.PasteboardType("public.jpeg"),
                NSPasteboard.PasteboardType("public.tiff"),
                NSPasteboard.PasteboardType("com.compuserve.gif"),
                NSPasteboard.PasteboardType("public.image")
            ]

            var foundImage: Data? = nil
            
            // Try to find the first available image in order of preference
            for type in supportedImageTypes {
                if let data = pboard.data(forType: type) {
                    foundImage = data
                    NSLog("Selected image type (Service): \(type)")
                    break // Take only the first matching format
                }
            }

            let textTypes: [NSPasteboard.PasteboardType] = [
                .string,
                .rtf,
                NSPasteboard.PasteboardType("public.plain-text")
            ]

            guard let selectedText = textTypes.lazy.compactMap({ pboard.string(forType: $0) }).first,
                  !selectedText.isEmpty else {
                error.pointee = "No text was selected" as NSString
                return
            }

            appState.selectedText = selectedText
            appState.selectedImages = foundImage.map { [$0] } ?? []
            isServiceTriggered = true

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                let window = PopupWindow(appState: self.appState)
                window.delegate = self

                self.closePopupWindow()
                self.popupWindow = window

                window.level = .floating
                window.collectionBehavior = [.moveToActiveSpace]

                window.positionNearMouse()
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()

                NSApp.activate()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isServiceTriggered = false
                }
            }
        } else {
            error.pointee = "Could not determine frontmost application" as NSString
            return
        }
    }

    private func closePopupWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let existingWindow = self.popupWindow as? PopupWindow {
                existingWindow.delegate = nil
                existingWindow.cleanup()
                existingWindow.close()

                self.appState.selectedImages = []
                self.popupWindow = nil
            }
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }
}

extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var carbon: UInt32 = 0
        if contains(.command) { carbon |= UInt32(cmdKey) }
        if contains(.option) { carbon |= UInt32(optionKey) }
        if contains(.control) { carbon |= UInt32(controlKey) }
        if contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}
