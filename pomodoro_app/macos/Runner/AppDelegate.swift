import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// 禁用 App Nap 的活动令牌，需常驻持有才生效。
  private var napToken: NSObjectProtocol?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // App Nap 会在窗口不可见时对定时器做 coalescing，导致后台时倒计时走不准
    // （表现为菜单栏/悬浮窗数字跳秒、变慢）。显式声明需要高精度计时。
    napToken = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated, .latencyCritical],
      reason: "番茄钟每秒计时")
    super.applicationDidFinishLaunching(notification)
  }

  /// 关掉窗口不退出 App：菜单栏倒计时依赖 Dart 侧每秒 tick，
  /// 若随窗口一起退出，最小化到菜单栏的意义就没了。
  /// 退出走 Cmd+Q 或菜单栏「退出松果」。
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// 窗口关闭后点 Dock 图标（或菜单栏「打开松果」）重新唤出主窗口。
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      for window in NSApp.windows where window is MainFlutterWindow {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        break
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
