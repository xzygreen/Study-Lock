import AppKit
import Testing
@testable import StudyLock

/// 不创建 FocusEngine,避免窗口测试读写真实专注记录或启动锁定。
/// 窗口替身不显示系统窗口,只记录恢复和置前操作。
@Suite(.serialized)
@MainActor
struct MainWindowTests {
    @Test(arguments: [false, true])
    func dockReopensClosedMainWindowRegardlessOfOtherVisibleWindows(hasVisibleWindows: Bool) {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        let window = WindowSpy()
        var reopenCount = 0
        delegate.registerMainWindow(window) { reopenCount += 1 }

        let useDefaultHandling = delegate.applicationShouldHandleReopen(
            app, hasVisibleWindows: hasVisibleWindows
        )

        #expect(!useDefaultHandling)
        #expect(reopenCount == 1)
        #expect(window.orderFrontCount == 0)
    }

    @Test func dockBringsExistingMainWindowToFrontWithoutOpeningAnotherScene() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        let window = WindowSpy()
        window.stubIsVisible = true
        var reopenCount = 0
        delegate.registerMainWindow(window) { reopenCount += 1 }

        _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: true)

        #expect(reopenCount == 0)
        #expect(window.orderFrontCount == 1)
        #expect(window.deminiaturizeCount == 0)
    }

    @Test func dockRestoresMinimizedMainWindow() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        let window = WindowSpy()
        window.stubIsMiniaturized = true
        var reopenCount = 0
        delegate.registerMainWindow(window) { reopenCount += 1 }

        _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false)

        #expect(!window.isMiniaturized)
        #expect(window.deminiaturizeCount == 1)
        #expect(window.orderFrontCount == 1)
        #expect(reopenCount == 0)
    }

    @Test func sharedOpenActionRecreatesClosedWindow() {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        let window = WindowSpy()
        var reopenCount = 0
        delegate.registerMainWindow(window) { reopenCount += 1 }

        delegate.showMainWindow()

        #expect(reopenCount == 1)
        #expect(window.orderFrontCount == 0)
    }

    @Test func subsequentReopensUseNewlyRegisteredWindow() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        let closedWindow = WindowSpy()
        let reopenedWindow = WindowSpy()
        var reopenCount = 0
        delegate.registerMainWindow(closedWindow) {
            reopenCount += 1
            reopenedWindow.stubIsVisible = true
            delegate.registerMainWindow(reopenedWindow) { reopenCount += 1 }
        }

        _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false)
        _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: true)
        delegate.showMainWindow()

        #expect(reopenCount == 1)
        #expect(closedWindow.orderFrontCount == 0)
        #expect(reopenedWindow.orderFrontCount == 2)
    }

    @Test func registrationPreservesSwiftUIWindowOwnership() {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        let window = WindowSpy()
        let windowDelegate = WindowDelegateSpy()
        window.delegate = windowDelegate
        window.isReleasedWhenClosed = true

        delegate.registerMainWindow(window) {}

        #expect(window.delegate === windowDelegate)
        #expect(window.isReleasedWhenClosed)
    }

    @Test func closingLastWindowKeepsApplicationRunning() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        #expect(!delegate.applicationShouldTerminateAfterLastWindowClosed(app))
    }
}

@MainActor
private final class WindowSpy: NSWindow {
    var stubIsVisible = false
    var stubIsMiniaturized = false
    private(set) var orderFrontCount = 0
    private(set) var deminiaturizeCount = 0

    init() {
        super.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
    }

    override var isVisible: Bool { stubIsVisible }
    override var isMiniaturized: Bool { stubIsMiniaturized }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        orderFrontCount += 1
        stubIsVisible = true
    }

    override func deminiaturize(_ sender: Any?) {
        deminiaturizeCount += 1
        stubIsMiniaturized = false
        stubIsVisible = true
    }
}

@MainActor
private final class WindowDelegateSpy: NSObject, NSWindowDelegate {}
