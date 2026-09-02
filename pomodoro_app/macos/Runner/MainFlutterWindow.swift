import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var statusItem: NSStatusItem?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    // 桌面布局为侧边栏 + 双栏：默认 1120×720，最小 900×600。
    // 关闭窗口状态恢复，避免系统用上次的旧尺寸覆盖初始大小。
    self.isRestorable = false
    self.setContentSize(NSSize(width: 1120, height: 720))
    self.minSize = NSSize(width: 900, height: 600)
    self.center()
    self.setFrame(self.frame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 菜单栏（屏幕右上角）剩余时间：NSStatusItem + Dart 每秒推送。
    installMenuBarTimer(engine: flutterViewController.engine)

    super.awakeFromNib()
  }

  private func installMenuBarTimer(engine: FlutterEngine) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
      button.image = NSImage(
        systemSymbolName: "timer",
        accessibilityDescription: "松果计时")
      button.imagePosition = .imageLeading
      button.target = self
      button.action = #selector(activateTimerWindow)
      button.toolTip = "松果 · 专注时光（点击回到计时窗口）"
    }
    statusItem = item

    let channel = FlutterMethodChannel(
      name: "pine/menu_bar",
      binaryMessenger: engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      let running = args["running"] as? Bool ?? false
      let title = args["title"] as? String ?? ""
      DispatchQueue.main.async {
        if running {
          self?.statusItem?.button?.title = "  \(title)"
        } else {
          self?.statusItem?.button?.title = ""
        }
      }
      result(nil)
    }
  }

  @objc private func activateTimerWindow() {
    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(nil)
  }
}
