import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSDraggingDestination, NSPopoverDelegate {
    private let translator = Translator()
    private let popover = NSPopover()
    private let menu = NSMenu()
    private var statusItem: NSStatusItem!
    private var outsideClickMonitor: Any?
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let qualityItem = NSMenuItem(title: "High-Quality Translation (Slower)", action: #selector(toggleHighQuality), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        setUpPopover()
        setUpStatusItem()
        registerHotKeys()
        closeOnEscape()
        showPopoverOnceStatusItemIsPlaced()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        showPopover()
        translator.ingest(pasteboard: sender.draggingPasteboard)
        return true
    }

    func popoverDidShow(_ notification: Notification) {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    @objc func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    @objc func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc func captureScreen() {
        let wasShown = popover.isShown
        popover.performClose(nil)
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard let image = await ScreenCapture.selectRegion() else {
                if wasShown { showPopover() }
                return
            }
            showPopover()
            await translator.ingest(image: image)
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent, event.type == .rightMouseUp || event.modifierFlags.contains(.control) else {
            togglePopover()
            return
        }
        popover.performClose(nil)
        statusItem.menu = menu
        sender.performClick(nil)
        statusItem.menu = nil
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

    private func showPopoverOnceStatusItemIsPlaced() {
        Task {
            for _ in 0..<40 where (statusItem.button?.window?.frame.height ?? 0) == 0 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            showPopover()
        }
    }

    private func setUpPopover() {
        let controller = NSHostingController(rootView: ContentView(translator: translator) { [weak self] in self?.captureScreen() })
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "Floatlate")
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.window?.registerForDraggedTypes([.fileURL, .png, .tiff, .string])
        button.window?.delegate = self

        menu.addItem(menuItem("Show Translator", #selector(showPopover), key: "t"))
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
    }

    private func menuItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.control, .option]
        item.target = self
        return item
    }

    private func registerHotKeys() {
        let modifiers = controlKey | optionKey
        HotKeyCenter.shared.register(keyCode: kVK_ANSI_T, modifiers: modifiers) { [weak self] in self?.togglePopover() }
        HotKeyCenter.shared.register(keyCode: kVK_ANSI_S, modifiers: modifiers) { [weak self] in self?.captureScreen() }
    }

    private func closeOnEscape() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == UInt16(kVK_Escape),
                  let window = popover.contentViewController?.view.window,
                  window.isKeyWindow, window.attachedSheet == nil,
                  !Self.isComposingText(in: window) else { return event }
            popover.performClose(nil)
            return nil
        }
    }

    private static func isComposingText(in window: NSWindow) -> Bool {
        (window.firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false
    }
}
