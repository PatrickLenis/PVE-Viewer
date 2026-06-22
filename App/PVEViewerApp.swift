import SwiftUI
import AppKit

@main
struct PVEViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = ProxmoxAppController()

    var body: some Scene {
        Window("PVE Viewer", id: "main") {
            ContentView(controller: controller)
                .tint(.proxmoxOrange)
                .frame(minWidth: 980, minHeight: 640)
                .background(MainWindowLifecycleView())
        }
        .windowStyle(.titleBar)
        .commands {
            SidebarCommands()
        }

        MenuBarExtra("PVE Viewer", image: "MenuBarIcon") {
            ProxmoxMenuBarContainer(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private struct ProxmoxMenuBarContainer: View {
    @ObservedObject var controller: ProxmoxAppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ProxmoxMenuBarView(
            store: controller.store,
            dashboardStore: controller.dashboardStore,
            openMainWindow: {
                openMainWindow()
            },
            openInstance: { instance in
                controller.focus(instance)
                openMainWindow()
            },
            openAPISettings: { instance in
                controller.openTokenSettings(for: instance)
                openMainWindow()
            },
            isActionInProgress: controller.dashboardStore.isActionInProgress,
            resourceAction: { action, resource, instance in
                Task {
                    await controller.dashboardStore.perform(action, on: resource, instance: instance)
                }
            },
            refreshAction: {
                Task { await controller.refreshAll(animated: true) }
            }
        )
        .task {
            controller.startPolling()
        }
    }

    private func openMainWindow() {
        DockVisibilityController.shared.showDockIcon()

        if focusMainWindow() {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            _ = focusMainWindow()
        }
    }

    private func focusMainWindow() -> Bool {
        guard let window = NSApp.windows.first(where: { $0.title == "PVE Viewer" }) else {
            return false
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }
}

private struct MainWindowLifecycleView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        registerWindow(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        registerWindow(from: nsView)
    }

    private func registerWindow(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            DockVisibilityController.shared.registerMainWindow(window)
        }
    }
}

private final class DockVisibilityController {
    static let shared = DockVisibilityController()

    private var mainWindows: [ObjectIdentifier: WeakWindow] = [:]
    private var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    private init() {}

    func registerMainWindow(_ window: NSWindow) {
        let id = ObjectIdentifier(window)

        mainWindows[id] = WeakWindow(window: window)
        showDockIcon()

        guard closeObservers[id] == nil else { return }
        closeObservers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.mainWindows.removeValue(forKey: id)
            self?.hideDockIconIfNoMainWindowRemains()
        }
    }

    func showDockIcon() {
        NSApp.setActivationPolicy(.regular)
    }

    private func hideDockIconIfNoMainWindowRemains() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            pruneClosedWindows()

            let hasOpenMainWindow = mainWindows.values.contains { weakWindow in
                guard let window = weakWindow.window else { return false }
                return window.isVisible || window.isMiniaturized
            }

            if !hasOpenMainWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func pruneClosedWindows() {
        mainWindows = mainWindows.filter { $0.value.window != nil }
    }
}

private struct WeakWindow {
    weak var window: NSWindow?
}
