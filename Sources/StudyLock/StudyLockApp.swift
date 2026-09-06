import AppKit
import SwiftUI

@main
struct StudyLockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = FocusEngine()

    var body: some Scene {
        Window("认真", id: MainWindowRegistration.sceneID) {
            RootView()
                .environmentObject(engine)
                .frame(minWidth: 980, minHeight: 680)
                .background(MainWindowRegistration(appDelegate: appDelegate))
                .onAppear {
                    appDelegate.attach(engine: engine)
                    NSApp.applicationIconImage = AppIcon.image
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        // 菜单栏项由 StatusItemController(原生 NSStatusItem)负责,
        // 不用 MenuBarExtra——原因见 StatusItemController 注释。
    }
}

/// 从主界面自己的视图获取窗口,避免把弹出面板或确认框误认成主窗口。
/// 保留 SwiftUI 的 openWindow 动作,窗口关闭并被释放后仍能重建同一个场景。
private struct MainWindowRegistration: NSViewRepresentable {
    static let sceneID = "main"

    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: WindowObserverView, context: Context) {
        view.onWindowAvailable = { [weak appDelegate, openWindow] window in
            appDelegate?.registerMainWindow(window) {
                openWindow(id: Self.sceneID)
            }
        }
        view.registerWindowIfAvailable()
    }

    final class WindowObserverView: NSView {
        var onWindowAvailable: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            registerWindowIfAvailable()
        }

        func registerWindowIfAvailable() {
            if let window {
                onWindowAvailable?(window)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var engine: FocusEngine?
    private weak var mainWindow: NSWindow?
    private var reopenMainWindow: (() -> Void)?
    private var statusItem: StatusItemController?

    /// 主窗口首次出现时接上引擎并建菜单栏项(只做一次)。
    func attach(engine: FocusEngine) {
        guard self.engine == nil else {
            return
        }
        self.engine = engine
        statusItem = StatusItemController(engine: engine, onOpenMainWindow: { [weak self] in
            self?.showMainWindow()
        })
    }

    func registerMainWindow(_ window: NSWindow, reopen: @escaping () -> Void) {
        mainWindow = window
        reopenMainWindow = reopen
    }

    func showMainWindow() {
        if let window = mainWindow, window.isVisible || window.isMiniaturized {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            // 关闭后由 SwiftUI 重建内容,不强行复用已退出场景的 NSWindow。
            // Window(id:) 是单窗口场景,反复点击不会创建多个主窗口。
            reopenMainWindow?()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 即使菜单栏面板可见,也必须恢复主窗口,不能依赖 hasVisibleWindows。
        showMainWindow()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 有会话或锁定时,退出必须走应用内冷静期 + 确认短语,不能用 Cmd+Q 秒过。
    /// 番茄专注阶段与应用内「提前结束」一样,直接拒绝。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let engine else {
            return .terminateNow
        }
        if engine.isPreparingToQuit {
            return .terminateNow
        }
        guard engine.isSessionActive || engine.isLockEnabled else {
            return .terminateNow
        }
        showMainWindow()
        engine.requestQuitConfirmation()
        return .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

enum AppIcon {
    static var image: NSImage {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()

        let bounds = NSRect(origin: .zero, size: size)
        let background = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 20, dy: 20),
            xRadius: 112,
            yRadius: 112
        )
        NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.18, alpha: 1).setFill()
        background.fill()

        let dial = NSBezierPath(
            ovalIn: NSRect(x: 106, y: 106, width: 300, height: 300)
        )
        NSColor(calibratedRed: 0.94, green: 0.97, blue: 0.96, alpha: 1).setFill()
        dial.fill()

        let center = NSPoint(x: 256, y: 256)
        let hand = NSBezierPath()
        hand.lineCapStyle = .round
        hand.lineWidth = 26
        hand.move(to: center)
        hand.line(to: NSPoint(x: 256, y: 342))
        hand.move(to: center)
        hand.line(to: NSPoint(x: 326, y: 218))
        NSColor(calibratedRed: 0.15, green: 0.55, blue: 0.43, alpha: 1).setStroke()
        hand.stroke()

        let hub = NSBezierPath(ovalIn: NSRect(x: 239, y: 239, width: 34, height: 34))
        NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.18, alpha: 1).setFill()
        hub.fill()

        image.unlockFocus()
        return image
    }
}
