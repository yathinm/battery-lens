import AppKit
import BatteryDomain
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var settingsController: NSWindowController?
    private var onboardingController: NSWindowController?
    private var model: BatteryAppModel?
    private var pinnedItems: [UUID: NSStatusItem] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private let dockCarousel = DockCarouselController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = BatteryAppModel()
        self.model = model

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: DevicePopoverView(
                model: model,
                openSettings: { [weak self] in self?.openSettings() }
            )
        )

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "battery.100", accessibilityDescription: "BatteryLens")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        model.onStatusTitleChange = { [weak self] title in
            self?.statusItem.button?.title = title
        }
        model.$devices
            .combineLatest(model.preferences.$dockCarousel, model.preferences.$showDock)
            .receive(on: RunLoop.main)
            .sink { [weak self] devices, carousel, showDock in
                self?.updatePinnedItems(devices)
                self?.dockCarousel.update(devices: devices, enabled: carousel && showDock)
            }
            .store(in: &cancellables)
        model.preferences.$showMenuBar
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible in self?.statusItem.isVisible = isVisible }
            .store(in: &cancellables)
        model.start()
        showOnboardingIfNeeded(model: model)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openSettings() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
        dockCarousel.stop()
    }

    @objc private func showMainPopover(_ sender: NSStatusBarButton) {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func updatePinnedItems(_ devices: [BatteryDevice]) {
        let pinned = Dictionary(uniqueKeysWithValues: devices.filter(\.isPinned).map { ($0.id, $0) })
        for id in pinnedItems.keys where pinned[id] == nil {
            if let item = pinnedItems.removeValue(forKey: id) { NSStatusBar.system.removeStatusItem(item) }
        }
        for (id, device) in pinned {
            let item = pinnedItems[id] ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            pinnedItems[id] = item
            guard let button = item.button else { continue }
            button.image = NSImage(systemSymbolName: deviceSymbol(device.category), accessibilityDescription: device.displayName)
            button.title = " " + (device.batteryLevel.map { "\($0)%" } ?? "—")
            button.target = self
            button.action = #selector(showMainPopover(_:))
            button.toolTip = "\(device.displayName): \(device.batteryLevel.map { "\($0)%" } ?? "Unavailable")"
        }
    }

    private func deviceSymbol(_ category: DeviceCategory) -> String {
        switch category {
        case .mac: "laptopcomputer"
        case .phone: "iphone"
        case .tablet: "ipad"
        case .watch: "applewatch"
        case .earbuds, .caseBattery: "airpodspro"
        case .mouse: "computermouse"
        case .keyboard: "keyboard"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .pencil: "applepencil"
        case .other: "battery.75"
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            model?.refresh(reason: .menuOpened)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit BatteryLens", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refresh() {
        model?.refresh(reason: .manual)
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    private func openSettings() {
        popover.performClose(nil)
        if settingsController == nil, let model {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: controller)
            window.title = "BatteryLens Settings"
            window.setContentSize(NSSize(width: 680, height: 520))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.center()
            window.isReleasedWhenClosed = false
            settingsController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    private func showOnboardingIfNeeded(model: BatteryAppModel) {
        guard !UserDefaults.standard.bool(forKey: "onboardingComplete") else { return }
        let view = OnboardingView(model: model) { [weak self] in
            UserDefaults.standard.set(true, forKey: "onboardingComplete")
            self?.onboardingController?.close()
            self?.onboardingController = nil
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome to BatteryLens"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        onboardingController = NSWindowController(window: window)
        NSApp.activate(ignoringOtherApps: true)
        onboardingController?.showWindow(nil)
    }
}
