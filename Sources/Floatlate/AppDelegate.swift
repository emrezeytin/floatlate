import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let translator = Translator()
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let qualityItem = NSMenuItem(title: "High-Quality Translation (Slower)", action: #selector(toggleHighQuality), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        panel = FloatingPanel(rootView: ContentView(translator: translator) { [weak self] in self?.captureScreen() })
        setUpStatusItem()
        registerHotKeys()
        hideOnEscape()
        showPanel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    @objc func togglePanel() {
        panel.isVisible ? panel.orderOut(nil) : showPanel()
    }

    @objc func captureScreen() {
        let wasVisible = panel.isVisible
        panel.orderOut(nil)
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard let image = await ScreenCapture.selectRegion() else {
                if wasVisible { showPanel() }
                return
            }
            showPanel()
            await translator.ingest(image: image)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            try service.status == .enabled ? service.unregister() : service.register()
        } catch {
            NSAlert(error: error).runModal()
        }
        loginItem.state = service.status == .enabled ? .on : .off
    }

    @objc private func toggleHighQuality() {
        translator.highQuality.toggle()
        qualityItem.state = translator.highQuality ? .on : .off
    }

    private func showPanel() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "Floatlate")

        let menu = NSMenu()
        menu.addItem(menuItem("Show Translator", #selector(togglePanel), key: "t"))
        menu.addItem(menuItem("Capture Text from Screen", #selector(captureScreen), key: "s"))
        menu.addItem(.separator())
        if #available(macOS 26.4, *) {
            qualityItem.target = self
            qualityItem.state = translator.highQuality ? .on : .off
            menu.addItem(qualityItem)
        }
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Floatlate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func menuItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.control, .option]
        item.target = self
        return item
    }

    private func registerHotKeys() {
        let modifiers = controlKey | optionKey
        HotKeyCenter.shared.register(keyCode: kVK_ANSI_T, modifiers: modifiers) { [weak self] in self?.togglePanel() }
        HotKeyCenter.shared.register(keyCode: kVK_ANSI_S, modifiers: modifiers) { [weak self] in self?.captureScreen() }
    }

    private func hideOnEscape() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let panel = self?.panel, event.keyCode == UInt16(kVK_Escape), panel.isKeyWindow, panel.attachedSheet == nil else { return event }
            panel.orderOut(nil)
            return nil
        }
    }
}
