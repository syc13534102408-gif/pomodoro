import Cocoa

/// 悬浮置顶计时小窗。
///
/// 与菜单栏倒计时同源：文案与配色由 Dart 每秒经 `pine/menu_bar` 推送，
/// 这里只负责渲染，不自己计时，避免出现第二份状态。
///
/// 关键点（决定「全屏 App 里也能看见」）：
/// - `collectionBehavior` 含 `.fullScreenAuxiliary`：才有资格出现在全屏空间；
/// - `canJoinAllSpaces`：跟随切换桌面；
/// - `level = .statusBar`：高于普通窗口与全屏窗口。
/// 悬浮窗可拖动，位置与开关存 UserDefaults（原生自治，不占用 Dart 存储模型）。
final class FloatingTimerPanel: NSPanel {
  static let shared = FloatingTimerPanel()

  /// 点击（未拖动）时的动作，由持有通道的窗口注入。
  var onClick: (() -> Void)?
  /// 右键菜单动作回传，取值与菜单栏一致：toggle / complete / discard。
  var onAction: ((String) -> Void)?

  private static let enabledKey = "pine.overlayEnabled"
  private static let originKey = "pine.overlayOrigin"
  private static let size = NSSize(width: 168, height: 74)

  private let headLabel = NSTextField(labelWithString: "专注中")
  private let timeLabel = NSTextField(labelWithString: "00:00")
  private let progressView = PineProgressView()

  private var lastHead: String?
  private var lastTime: String?
  private var lastTint: Int?
  private var lastProgress: Double?

  /// 用户开关，菜单栏「悬浮计时器」切换。默认开启。
  var userEnabled: Bool {
    get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
    set {
      UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
      if !newValue { setVisible(false) }
    }
  }

  private init() {
    super.init(
      contentRect: NSRect(origin: .zero, size: Self.size),
      styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    // 置顶 + 跨桌面 + 允许出现在全屏空间之上。
    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    hidesOnDeactivate = false
    isMovable = false
    isMovableByWindowBackground = false

    let root = PineDragView(frame: NSRect(origin: .zero, size: Self.size))
    root.onClick = { [weak self] in self?.onClick?() }
    let effect = NSVisualEffectView(frame: root.bounds)
    effect.autoresizingMask = [.width, .height]
    effect.material = .hudWindow
    effect.blendingMode = .behindWindow
    effect.state = .active
    effect.wantsLayer = true
    effect.layer?.cornerRadius = 14
    effect.layer?.masksToBounds = true
    root.addSubview(effect)
    contentView = root

    headLabel.font = .systemFont(ofSize: 11, weight: .medium)
    headLabel.textColor = NSColor.white.withAlphaComponent(0.72)
    headLabel.alignment = .center
    headLabel.lineBreakMode = .byTruncatingTail
    headLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    timeLabel.font = .monospacedDigitSystemFont(ofSize: 27, weight: .semibold)
    timeLabel.textColor = .white
    timeLabel.alignment = .center

    let stack = NSStackView(views: [headLabel, timeLabel])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    effect.addSubview(stack)
    progressView.translatesAutoresizingMaskIntoConstraints = false
    effect.addSubview(progressView)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 9),
      progressView.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
      progressView.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
      progressView.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -11),
      progressView.heightAnchor.constraint(equalToConstant: 4),
    ])
  }

  /// 每秒一次的刷新入口。`active` 为 false（无进行中会话）时自动隐藏。
  func apply(head: String, elapsed: String, progress: Double, tintArgb: Int, active: Bool) {
    if head != lastHead {
      headLabel.stringValue = head
      lastHead = head
    }
    if elapsed != lastTime {
      timeLabel.stringValue = elapsed
      lastTime = elapsed
    }
    if abs(progress - (lastProgress ?? -1)) > 0.001 {
      progressView.fraction = progress
      lastProgress = progress
    }
    if tintArgb != lastTint {
      let tint = pineColor(tintArgb)
      timeLabel.textColor = tint
      progressView.tint = tint
      lastTint = tintArgb
    }
    setVisible(userEnabled && active)
    // 空闲期隐藏累积的状态差异会在重新显示时一次性补齐，这里无需额外处理。
  }

  private func setVisible(_ visible: Bool) {
    if visible {
      if !isVisible { restoreOrigin() }
      orderFrontRegardless()
    } else if isVisible {
      saveOrigin()
      orderOut(nil)
    }
  }

  // ==================== 位置 ====================

  /// 首次显示或位置非法时，落在主屏右上角、菜单栏下方。
  private func restoreOrigin() {
    if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
      let parts = saved.split(separator: ",").compactMap { Double($0) }
      if parts.count == 2, let screen = NSScreen.screens.first(where: {
        $0.frame.contains(NSPoint(x: parts[0], y: parts[1]))
      }) ?? NSScreen.main {
        let rect = NSRect(
          x: parts[0], y: parts[1],
          width: Self.size.width, height: Self.size.height)
        // 换显示器/改分辨率后旧坐标可能跑出屏幕，越界就回退到默认位置。
        if screen.visibleFrame.insetBy(dx: -40, dy: -40).contains(rect) {
          setFrameOrigin(NSPoint(x: parts[0], y: parts[1]))
          return
        }
      }
    }
    guard let screen = NSScreen.main else { return }
    let visible = screen.visibleFrame
    setFrameOrigin(NSPoint(
      x: visible.maxX - Self.size.width - 14,
      y: visible.maxY - Self.size.height - 6))
  }

  private func saveOrigin() {
    let origin = frame.origin
    UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: Self.originKey)
  }

  /// 拖动结束后由内容视图回调。
  func persistOrigin() { saveOrigin() }

  private func pineColor(_ argb: Int) -> NSColor {
    let value = UInt32(truncatingIfNeeded: argb)
    return NSColor(
      red: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 1)
  }

  // ==================== 右键菜单 ====================

  /// 供内容视图在右键时弹出。
  func popupMenu(at point: NSPoint) {
    let menu = NSMenu()
    for (title, id) in [("开始 / 暂停", "toggle"), ("完成", "complete"), ("重置", "discard")] {
      let item = NSMenuItem(title: title, action: #selector(handleAction(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = id
      menu.addItem(item)
    }
    menu.addItem(NSMenuItem.separator())
    let open = NSMenuItem(
      title: "打开松果", action: #selector(openMainWindow), keyEquivalent: "")
    open.target = self
    menu.addItem(open)
    let hide = NSMenuItem(
      title: "隐藏悬浮计时器", action: #selector(hideSelf), keyEquivalent: "")
    hide.target = self
    menu.addItem(hide)
    menu.popUp(positioning: nil, at: point, in: contentView)
  }

  @objc private func handleAction(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    onAction?(id)
  }

  @objc private func openMainWindow() { onClick?() }

  @objc private func hideSelf() { userEnabled = false }

  /// 供菜单栏条目读取当前开关状态。
  func isUserEnabled() -> Bool { userEnabled }
}

/// 悬浮窗内容视图：自己实现拖动（比 isMovableByWindowBackground 更容易区分点击与拖动），
/// 右键弹出操作菜单。
private final class PineDragView: NSView {
  var onClick: (() -> Void)?

  private var startMouse: NSPoint?
  private var startOrigin: NSPoint?
  private var moved = false

  override func mouseDown(with event: NSEvent) {
    if event.type == .rightMouseDown {
      super.mouseDown(with: event)
      return
    }
    startMouse = NSEvent.mouseLocation
    startOrigin = window?.frame.origin
    moved = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard let mouse = startMouse, let origin = startOrigin, let window = window else { return }
    let current = NSEvent.mouseLocation
    window.setFrameOrigin(NSPoint(
      x: origin.x + current.x - mouse.x,
      y: origin.y + current.y - mouse.y))
    if abs(current.x - mouse.x) > 3 || abs(current.y - mouse.y) > 3 { moved = true }
  }

  override func mouseUp(with event: NSEvent) {
    if event.type == .rightMouseDown { return }
    if moved {
      FloatingTimerPanel.shared.persistOrigin()
    } else if event.type == .leftMouseUp {
      onClick?()
    }
    startMouse = nil
    startOrigin = nil
    moved = false
  }

  override func rightMouseDown(with event: NSEvent) {
    FloatingTimerPanel.shared.popupMenu(at: event.locationInWindow)
  }
}

/// 悬浮窗底部进度条，随阶段配色。
private final class PineProgressView: NSView {
  var fraction: Double = 0 { didSet { needsDisplay = true } }
  var tint: NSColor = .white { didSet { needsDisplay = true } }

  override func draw(_ dirtyRect: NSRect) {
    let radius = bounds.height / 2
    NSColor.white.withAlphaComponent(0.18).setFill()
    NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    var filled = bounds
    filled.size.width = max(bounds.height, bounds.width * CGFloat(min(max(fraction, 0), 1)))
    tint.setFill()
    NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
  }
}
