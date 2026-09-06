import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var statusItem: NSStatusItem?
  // 通道必须由窗口持有，否则方法回调处理器可能随局部变量释放。
  private var menuBarChannel: FlutterMethodChannel?

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
      // 叶子图标对应品牌"松果"
      button.image = NSImage(
        systemSymbolName: "leaf.fill",
        accessibilityDescription: "松果计时")
      button.imagePosition = .imageLeading
      button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
      button.target = self
      button.action = #selector(activateTimerWindow)
      button.toolTip = "松果 · 专注时光（点击回到计时窗口）"
      // 【诊断】初始标题：若 3 秒后变为"来自Dart OK"则通道正常。
      button.title = "等待消息"
    }
    statusItem = item

    let channel = FlutterMethodChannel(
      name: "pine/menu_bar",
      binaryMessenger: engine.binaryMessenger)
    menuBarChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let title = (call.arguments as? [String: Any])?["title"] as? String ?? ""
      DispatchQueue.main.async {
        let state = (self == nil ? "self=nil" : "self=ok")
        let button = (self?.statusItem?.button == nil ? "btn=nil" : "btn=ok")
        try? ("\(Date()): self=\(state) \(button) title=[\(title)]\n").write(
          toFile: "/tmp/pine-native-channel.log",
          atomically: true,
          encoding: .utf8)
        self?.statusItem?.button?.title = title
      }
      result(nil)
    }
  }

  @objc private func activateTimerWindow() {
    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(nil)
  }
}
