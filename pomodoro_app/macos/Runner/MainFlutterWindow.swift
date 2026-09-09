import Cocoa
import FlutterMacOS

/// 主窗口 + 菜单栏（屏幕右上角状态栏）计时显示。
///
/// 分工：
/// - 文案与配色由 Dart 每秒通过 MethodChannel `pine/menu_bar` 推送（`update`）；
/// - 点击菜单栏图标弹出菜单，动作（开始/暂停、完成、重置）回传 Dart（`action`），
///   由计时引擎统一处理，避免原生与 Flutter 各存一份计时状态。
/// 通道必须由窗口持有，否则方法回调处理器会随局部变量释放。
class MainFlutterWindow: NSWindow, NSMenuDelegate {
  private var statusItem: NSStatusItem?
  private var menuBarChannel: FlutterMethodChannel?

  /// Dart 最近一次推送的状态，菜单展开时用于渲染条目文案。
  private var menuState: [String: Any] = [:]

  /// 上一次渲染的菜单栏文本与配色，用于跳过无变化的重绘（暂停/空闲时每秒都会推送）。
  private var lastTitle: String?
  private var lastTint: Int?

  /// 菜单栏「悬浮计时器」开关条目，展开菜单时同步勾选状态。
  private var overlayMenuItem: NSMenuItem?

  private enum MenuTag: Int {
    case head = 1
    case detail
    case primary
    case confirm
    case reset
    case overlay
    case open
    case quit
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // 方向 B「专注舱」：默认小窗 500×640，最小 440×600。
    // 桌面布局为单舱 + 右滑抽屉（统计/设置）；窗口拖宽只留白、内容不拉伸。
    // 关闭窗口状态恢复，避免系统用上次的旧尺寸覆盖初始大小。
    self.isRestorable = false
    // 关窗后窗口对象必须存活：菜单栏计时依赖窗口持有的 FlutterEngine 与通道，
    // 若随窗口一起释放，倒计时和菜单动作都会失效。
    self.isReleasedWhenClosed = false
    self.setContentSize(NSSize(width: 500, height: 640))
    self.minSize = NSSize(width: 440, height: 600)
    self.center()
    self.setFrame(self.frame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    installMenuBarTimer(engine: flutterViewController.engine)

    super.awakeFromNib()
  }

  // ==================== 菜单栏 ====================

  private func installMenuBarTimer(engine: FlutterEngine) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    // 固定出足够宽度，避免菜单栏拥挤时把可变宽度压缩为只剩图标区域。
    item.length = 92
    // 先持有再配置：render 内部读的是 self.statusItem。
    statusItem = item
    if let button = item.button {
      // 状态栏优先保证倒计时文字可见。部分 macOS 版本在 NSStatusItem
      // 同时设置 image 与 title 时会只绘制图标，因此这里使用纯文字按钮。
      button.image = nil
      button.imagePosition = .noImage
      button.toolTip = "松果 · 专注时光（点击查看菜单）"
    }
    // 首帧占位：Dart 就绪后（约 1 秒内）会被真实状态覆盖。
    render(title: "松果", tintArgb: PineARGB.muted)

    let menu = buildStatusBarMenu()
    menu.delegate = self
    item.menu = menu

    // 悬浮小窗与菜单栏共用同一条通道：动作回传给 Dart 的计时引擎，
    // 点击空白区域则唤出主窗口。
    let panel = FloatingTimerPanel.shared
    panel.onAction = { [weak self] id in self?.send(action: id) }
    panel.onClick = { [weak self] in self?.activateTimerWindow() }

    let channel = FlutterMethodChannel(
      name: "pine/menu_bar",
      binaryMessenger: engine.binaryMessenger)
    menuBarChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if let args = call.arguments as? [String: Any] {
        self?.menuState = args
        DispatchQueue.main.async { self?.applyState(args) }
      }
      result(nil)
    }
  }

  private func buildStatusBarMenu() -> NSMenu {
    let menu = NSMenu()
    // 手动控制每个条目的可用性，避免 AppKit 自动禁用无 target 的条目之外的内容。
    menu.autoenablesItems = false

    let head = NSMenuItem(title: "松果 · 专注时光", action: nil, keyEquivalent: "")
    head.tag = MenuTag.head.rawValue
    head.isEnabled = false
    menu.addItem(head)

    let detail = NSMenuItem(title: "未开始", action: nil, keyEquivalent: "")
    detail.tag = MenuTag.detail.rawValue
    detail.isEnabled = false
    menu.addItem(detail)

    menu.addItem(NSMenuItem.separator())

    menu.addItem(actionItem(title: "开始", tag: .primary))
    menu.addItem(actionItem(title: "完成", tag: .confirm))
    menu.addItem(actionItem(title: "重置（不记录）", tag: .reset))

    menu.addItem(NSMenuItem.separator())

    let overlay = actionItem(title: "悬浮计时器", tag: .overlay)
    overlayMenuItem = overlay
    menu.addItem(overlay)

    menu.addItem(NSMenuItem.separator())

    menu.addItem(actionItem(title: "打开松果", tag: .open))
    menu.addItem(actionItem(title: "退出松果", tag: .quit))
    return menu
  }

  private func actionItem(title: String, tag: MenuTag) -> NSMenuItem {
    let item = NSMenuItem(
      title: title,
      action: #selector(handleMenuAction(_:)),
      keyEquivalent: "")
    item.tag = tag.rawValue
    item.target = self
    return item
  }

  /// 菜单展开前按最新状态刷新条目文案。Dart 每秒推送一次，这里只是取缓存渲染。
  func menuWillOpen(_ menu: NSMenu) {
    let state = menuState
    menu.item(withTag: MenuTag.head.rawValue)?.title =
      string(state, "head") ?? "松果 · 专注时光"
    menu.item(withTag: MenuTag.detail.rawValue)?.title = string(state, "detail") ?? ""
    menu.item(withTag: MenuTag.primary.rawValue)?.title = string(state, "primary") ?? "开始"
    menu.item(withTag: MenuTag.confirm.rawValue)?.title = string(state, "confirm") ?? "完成"
    menu.item(withTag: MenuTag.reset.rawValue)?.isEnabled =
      (state["canReset"] as? NSNumber)?.boolValue ?? false
    let overlay = menu.item(withTag: MenuTag.overlay.rawValue)
    overlay?.state = FloatingTimerPanel.shared.isUserEnabled() ? .on : .off
  }

  private func applyState(_ state: [String: Any]) {
    let title = string(state, "title") ?? "松果"
    let tintArgb = (state["tint"] as? NSNumber)?.intValue ?? PineARGB.muted
    // 悬浮窗自己判断变化，必须放在菜单栏重绘的短路之前，否则暂停时不会刷新。
    updateOverlay(state, tintArgb: tintArgb)
    // 暂停/空闲时标题不变，跳过重绘避免每秒重建富文本。
    if title == lastTitle && tintArgb == lastTint { return }
    render(title: title, tintArgb: tintArgb)
  }

  /// 把 Dart 推送的状态同步到悬浮置顶小窗；无进行中会话时它会自动隐藏。
  private func updateOverlay(_ state: [String: Any], tintArgb: Int) {
    FloatingTimerPanel.shared.apply(
      head: string(state, "head") ?? "专注中",
      elapsed: string(state, "elapsed") ?? "00:00",
      progress: (state["progress"] as? NSNumber)?.doubleValue ?? 0,
      tintArgb: tintArgb,
      active: (state["active"] as? NSNumber)?.boolValue ?? false)
  }

  private func render(title: String, tintArgb: Int) {
    guard let button = statusItem?.button else { return }
    let tint = pineColor(tintArgb)
    // 等宽数字：倒计时逐秒变化时宽度不跳动。
    let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    // 明确设置文字颜色，避免深色菜单栏沿用默认暗色导致标题不可见。
    button.attributedTitle = NSAttributedString(
      string: title,
      attributes: [.font: font, .foregroundColor: tint])
    button.contentTintColor = tint
    lastTitle = title
    lastTint = tintArgb
  }

  private func string(_ state: [String: Any], _ key: String) -> String? {
    guard let value = state[key] as? String, !value.isEmpty else { return nil }
    return value
  }

  private func pineColor(_ argb: Int) -> NSColor {
    let value = UInt32(truncatingIfNeeded: argb)
    return NSColor(
      red: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 1)
  }

  @objc private func handleMenuAction(_ sender: NSMenuItem) {
    guard let tag = MenuTag(rawValue: sender.tag) else { return }
    switch tag {
    case .primary:
      send(action: "toggle")
    case .confirm:
      send(action: "complete")
    case .reset:
      send(action: "discard")
    case .overlay:
      let panel = FloatingTimerPanel.shared
      panel.userEnabled = !panel.isUserEnabled()
      sender.state = panel.isUserEnabled() ? .on : .off
    case .open:
      activateTimerWindow()
    case .quit:
      NSApp.terminate(nil)
    default:
      break
    }
  }

  private func send(action id: String) {
    menuBarChannel?.invokeMethod("action", arguments: ["id": id]) { _ in
      // 动作由 Dart 侧的计时引擎执行；这里不需要返回值。
    }
  }

  @objc private func activateTimerWindow() {
    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(nil)
  }
}

/// Dart 侧 PineColors 的 ARGB 兜底值（原生不会改业务配色，只用于首帧）。
private enum PineARGB {
  static let muted = 0xFF939C96
}
