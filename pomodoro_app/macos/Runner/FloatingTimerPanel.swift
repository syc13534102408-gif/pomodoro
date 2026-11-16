import Cocoa

/// 悬浮置顶计时小窗（V4 素纸「墨条」）。
///
/// 与菜单栏倒计时同源：文案与配色由 Dart 每秒经 `pine/menu_bar` 推送，
/// 这里只负责渲染，不自己计时，避免出现第二份状态。
///
/// 关键点（决定「全屏 App 里也能看见」）：
/// - `collectionBehavior` 含 `.fullScreenAuxiliary`：才有资格出现在全屏空间；
/// - `canJoinAllSpaces`：跟随切换桌面；
/// - `level = .statusBar`：高于普通窗口与全屏窗口。
/// 悬浮窗可拖动，位置与开关存 UserDefaults（原生自治，不占用 Dart 存储模型）。
///
/// 形态（2026-11-16 定稿，评审稿 `04-timer-lab` 的 B 版「墨条」）：
/// 一张 196×46 的纸卡 —— 左是宋体阶段词，右是等宽读数，底下一条**墨条**。
/// 墨条不是水位：笔身实、末端 16pt 用竖向笔丝切成飞白，所以读起来是「一笔写
/// 到这里」，不是「水涨到这里」。潮汐那一套（浪、前滩、泡沫痕、CA 摆动）已整体删除。
///
/// 三态（与设计稿一一对应）：
/// - 专注/短休/吃饭：墨条用阶段色（Dart 推送的 tint）；
/// - 暂停：阶段词变成「已暂停」、墨条同时落灰（tint 由 Dart 换成中性灰），
///   并在墨条上覆一条 12% 斜纹——三个信号同时给，不靠动画停格；
/// - 超时：读数带 `+` 前缀、tint 换赭石，墨条满格。
final class FloatingTimerPanel: NSPanel {
  static let shared = FloatingTimerPanel()

  /// 点击（未拖动）时的动作，由持有通道的窗口注入。
  var onClick: (() -> Void)?
  /// 右键菜单动作回传，取值与菜单栏一致：toggle / complete / discard。
  var onAction: ((String) -> Void)?

  private static let enabledKey = "pine.overlayEnabled"
  /// V4 起换键：旧键里存的是「压在主窗右栏上」的那个坐标，
  /// 沿用旧值会让新的默认落点（窗口外）永远不生效。
  private static let originKey = "pine.overlayOriginV4"
  /// 只有「用户亲手拖过」的位置才值得记住。自动摆位/自动隐藏如果也写进去，
  /// 会把一次开机时的临时坐标固化成永久位置（本次实测就踩了这个坑）。
  private static let userPlacedKey = "pine.overlayUserPlaced"

  /// 固定尺寸：不再随读数位数伸缩（伸缩会让墨条长度跳动，读不出进度）。
  private static let panelSize = NSSize(width: 176, height: 46)

  /// Dart 在暂停时推送的阶段词，用来点亮斜纹。
  private static let pausedPhase = "已暂停"

  private let phaseLabel = NSTextField(labelWithString: "专注中")
  private let timeLabel = NSTextField(labelWithString: "00:00")
  private let inkView = InkStrokeView()
  private var effectView = NSView()

  private var lastPhase: String?
  private var lastTime: String?
  private var lastTint: Int?
  private var lastProgress: Double?
  /// 当前位置是否仍是「自动摆放」（用户没拖过）。用来在启动后补一次判位。
  private var autoPlaced = false
  /// 本次运行是否已经摆过位。系统恢复可能让面板一上来就是 visible，
  /// 单靠 `isVisible` 判断会漏掉摆位。
  private var didPlace = false

  /// 用户开关，菜单栏「悬浮计时器」切换。默认开启。
  var userEnabled: Bool {
    get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
    set {
      UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
      if !newValue { setVisible(false) }
    }
  }

  private init() {
    let size = Self.panelSize
    super.init(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    hidesOnDeactivate = false
    isMovable = false
    isMovableByWindowBackground = false
    // 关掉系统窗口恢复：它会把这枚面板的旧坐标原样搬回来，压过我们的默认摆位。
    isRestorable = false

    let root = PineDragView(frame: NSRect(origin: .zero, size: size))
    root.onClick = { [weak self] in self?.onClick?() }
    // 素纸：纸面底 #FFFEFA + 1px 定界线 #D0C8BA + 10pt 书页切角。
    let effect = NSView(frame: root.bounds)
    effect.autoresizingMask = [.width, .height]
    effect.wantsLayer = true
    effect.layer?.backgroundColor = NSColor(
      srgbRed: 1.0, green: 0.9961, blue: 0.9804, alpha: 1.0).cgColor
    effect.layer?.cornerRadius = 10
    effect.layer?.masksToBounds = true
    effect.layer?.borderWidth = 1
    effect.layer?.borderColor = NSColor(
      srgbRed: 0.8157, green: 0.7843, blue: 0.7294, alpha: 1.0).cgColor
    root.addSubview(effect)
    effectView = effect
    contentView = root

    // 阶段词：宋体 12，中墨。宋体在 macOS 上必有；取不到就退回系统衬线。
    phaseLabel.font = NSFont(name: "Songti SC", size: 12)
      ?? .systemFont(ofSize: 12, weight: .regular)
    phaseLabel.textColor = NSColor(
      srgbRed: 0.3373, green: 0.3137, blue: 0.2902, alpha: 1.0)
    phaseLabel.lineBreakMode = .byTruncatingTail
    phaseLabel.setContentHuggingPriority(.required, for: .horizontal)
    phaseLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    // 读数：等宽数字 19，浓墨。tabular 保证每秒跳字时宽度不变。
    timeLabel.font = .monospacedDigitSystemFont(ofSize: 19, weight: .semibold)
    timeLabel.textColor = NSColor(
      srgbRed: 0.1333, green: 0.1137, blue: 0.0980, alpha: 1.0)
    timeLabel.alignment = .right
    timeLabel.setContentHuggingPriority(.required, for: .horizontal)
    timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    for view in [phaseLabel, timeLabel, inkView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      effect.addSubview(view)
    }

    NSLayoutConstraint.activate([
      phaseLabel.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
      phaseLabel.topAnchor.constraint(equalTo: effect.topAnchor, constant: 8),
      timeLabel.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
      timeLabel.firstBaselineAnchor.constraint(equalTo: phaseLabel.firstBaselineAnchor),
      timeLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: phaseLabel.trailingAnchor, constant: 8),
      inkView.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
      inkView.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
      inkView.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),
      inkView.heightAnchor.constraint(equalToConstant: 11),
    ])
  }

  /// 每秒一次的刷新入口。`active` 为 false（无进行中会话）时自动隐藏。
  func apply(
    head: String, phase: String, elapsed: String, progress: Double,
    over: Double, tintArgb: Int, active: Bool
  ) {
    if phase != lastPhase {
      lastPhase = phase
      phaseLabel.stringValue = phase
      inkView.paused = phase == Self.pausedPhase
    }
    if elapsed != lastTime {
      timeLabel.stringValue = elapsed
      lastTime = elapsed
    }
    if abs(progress - (lastProgress ?? -1)) > 0.001 {
      inkView.fraction = progress
      lastProgress = progress
    }
    if tintArgb != lastTint {
      inkView.tint = pineColor(tintArgb)
      lastTint = tintArgb
    }
    // 每秒重画一次：墨条只有 168×11，重画成本可以忽略，
    // 但能保证「暂停换色 / 满格 / 从后台切回」这些状态不会停在旧帧上。
    inkView.needsDisplay = true
    setVisible(userEnabled && active)
  }

  private func setVisible(_ visible: Bool) {
    if visible {
      if !didPlace { restoreOrigin(); didPlace = true }
      orderFrontRegardless()
    } else if isVisible {
      // 自动摆位的位置不落库（见 userPlacedKey 注释）。
      if !autoPlaced { saveOrigin() }
      orderOut(nil)
    }
  }

  // ==================== 位置 ====================

  /// 首次显示或位置非法时自动摆位——这是「不遮挡」的唯一可靠解法。
  ///
  /// 旧行为是落在主屏右上角（`maxX-14, maxY-6`），实测正好压在主窗右栏顶部
  /// （气泡 149×28 @ (1232,160)，主窗右边界 1279，横向重叠 47pt）。
  /// 现在的规则：① 四角里找完全空着的一个；② 都占满（大窗 + 小屏，本机就是）
  /// 就跨坐在主窗下沿，只压住窗口底部那圈留白；③ 没有主窗才退回右下角。
  private func restoreOrigin() {
    let size = Self.panelSize
    let userPlaced = UserDefaults.standard.bool(forKey: Self.userPlacedKey)
    if userPlaced, let saved = UserDefaults.standard.string(forKey: Self.originKey) {
      let parts = saved.split(separator: ",").compactMap { Double($0) }
      if parts.count == 2, let screen = NSScreen.screens.first(where: {
        $0.frame.contains(NSPoint(x: parts[0], y: parts[1]))
      }) ?? NSScreen.main {
        let rect = NSRect(
          x: parts[0], y: parts[1], width: size.width, height: size.height)
        if screen.visibleFrame.insetBy(dx: -40, dy: -40).contains(rect) {
          setFrame(
            NSRect(origin: NSPoint(x: parts[0], y: parts[1]), size: size),
            display: true)
          autoPlaced = false
          return
        }
      }
    }
    guard let screen = NSScreen.main else { return }
    setFrameOrigin(defaultOrigin(on: screen, size: size))
    autoPlaced = true
    // 开机自启时主窗比悬浮窗晚一帧才建好，这时看到的 `NSApp.windows` 还是空的。
    // 1.2 秒后再判一次，避免整个会话都停在「压住主窗」的位置上。
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
      guard let self, self.autoPlaced, self.isVisible,
            let screen = NSScreen.main else { return }
      let target = self.defaultOrigin(on: screen, size: Self.panelSize)
      if abs(target.x - self.frame.origin.x) > 1
        || abs(target.y - self.frame.origin.y) > 1 {
        self.setFrameOrigin(target)
      }
    }
  }

  /// 摆位优先级：右侧栏 → 右下角 → 跨坐主窗下沿。
  ///
  /// 本机实测：屏 1470×956，可见区 (0,83,1470,836)；主窗 1100 宽时右侧还剩
  /// (1470-1100)/2 = 185pt 的桌面，刚好够 176pt 的气泡整只站进去——
  /// 这是唯一能做到「一点都不压住窗口」的位置。
  private func defaultOrigin(on screen: NSScreen, size: NSSize) -> NSPoint {
    let visible = screen.visibleFrame
    let others = NSApp.windows
      .filter { $0 !== self && $0.isVisible && !($0 is NSPanel) && $0.frame.width > 200 }
      .map { $0.frame }
    // 不做外扩探测：本机右侧栏只有 185pt，外扩 8pt 就会把唯一可用的位置判掉。
    func free(_ point: NSPoint) -> Bool {
      let probe = NSRect(origin: point, size: size)
      return !others.contains(where: { $0.intersects(probe) })
    }
    let rightX = visible.maxX - size.width - 6
    let candidates = [
      // ① 右侧栏顶端（与菜单栏留 8pt）
      NSPoint(x: rightX, y: visible.maxY - size.height - 8),
      // ② 右侧栏底端
      NSPoint(x: rightX, y: visible.minY + 8),
      // ③ 左侧栏顶端
      NSPoint(x: visible.minX + 8, y: visible.maxY - size.height - 8),
      // ④ 左侧栏底端
      NSPoint(x: visible.minX + 8, y: visible.minY + 8),
    ]
    for point in candidates where free(point) { return point }
    // ⑤ 都没有空位（超大窗）：跨坐主窗下沿，只压住窗口底部那圈留白。
    if let main = others.max(by: { $0.width < $1.width }) {
      let x = max(visible.minX + 8, min(main.maxX - size.width - 8, rightX))
      let y = max(visible.minY + 6, main.minY - size.height / 2)
      return NSPoint(x: x, y: y)
    }
    return candidates[0]
  }

  private func saveOrigin() {
    let origin = frame.origin
    UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: Self.originKey)
  }

  /// 拖动结束后由内容视图回调。
  func persistOrigin() {
    autoPlaced = false
    UserDefaults.standard.set(true, forKey: Self.userPlacedKey)
    saveOrigin()
  }

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
      title: "打开 pinecore", action: #selector(openMainWindow), keyEquivalent: "")
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

/// 纸卡底部的那道墨条（评审稿 B 版）。
///
/// 画四层：
/// 1. **淡痕**（3pt、纸线色 55%）：表示「这一趟有多长」，不抢注意力；
/// 2. **笔身**（7pt、阶段色）：已历部分，左端方头（贴着起点），右端圆角；
/// 3. **飞白**（末端 16pt）：12 根竖向笔丝，高度与浓度按确定性伪随机散开，
///    读起来是笔锋收干，不是水面断裂；
/// 4. **暂停斜纹**：45° 每 4pt 一条 1pt 淡墨，覆在整条上（暂停时笔身本身
///    已被 Dart 换成中性灰，两者叠加即「冻住了」）。
///
/// 纯 Cocoa 无 Flutter 依赖，`draw(_:)` 里全部即时绘制，无图层动画。
final class InkStrokeView: NSView {
  /// 已历比例 0…1。
  var fraction: Double = 0 { didSet { needsDisplay = true } }
  /// 阶段色（专注檀褐 / 短休青瓷 / 吃饭赭石 / 超时赭石）。
  var tint: NSColor = NSColor(
    srgbRed: 0.5608, green: 0.3216, blue: 0.2510, alpha: 1) {
    didSet { needsDisplay = true }
  }
  /// 暂停：覆斜纹并抹掉飞白。
  var paused: Bool = false { didSet { needsDisplay = true } }

  /// 笔身高度与淡痕高度。
  private static let bodyHeight: CGFloat = 7
  private static let trackHeight: CGFloat = 3
  /// 飞白段的长度。
  private static let dryLength: CGFloat = 16
  /// 飞白笔丝数量。
  private static let bristles = 12

  override var isFlipped: Bool { true }

  /// 确定性伪随机：同一笔丝位置每帧取到同一组数值，重绘不会闪。
  private func noise(_ index: Int) -> CGFloat {
    let value = sin(Double(index) * 12.9898 + 4.1414) * 43758.5453
    return CGFloat(value - floor(value))
  }

  override func draw(_ dirtyRect: NSRect) {
    let width = bounds.width
    let height = bounds.height
    guard width > 2, height > 2 else { return }

    let paperLine = NSColor(srgbRed: 0.8157, green: 0.7843, blue: 0.7294, alpha: 1)

    // 1) 淡痕：整条的总长参照。
    let trackRect = NSRect(
      x: 0, y: (height - Self.trackHeight) / 2,
      width: width, height: Self.trackHeight)
    paperLine.withAlphaComponent(0.55).setFill()
    NSBezierPath(roundedRect: trackRect, xRadius: 1.5, yRadius: 1.5).fill()

    // 2) 笔身 + 3) 飞白：笔身永远让出末端 14pt 给笔锋，
    //    所以「写满」的时候也不是一根圆头进度条，而是笔收在最后一根笔丝上。
    let filled = CGFloat(min(max(fraction, 0), 1)) * width
    if filled > 0.6 {
      let tip = min(14, filled)
      let bodyEnd = filled - tip
      if bodyEnd > 0.6 {
        let bodyRect = NSRect(
          x: 0, y: (height - Self.bodyHeight) / 2,
          width: bodyEnd, height: Self.bodyHeight)
        tint.setFill()
        NSBezierPath(roundedRect: bodyRect, xRadius: 2, yRadius: 2).fill()
      }
      if !paused {
        let midY = height / 2
        for index in 0..<Self.bristles {
          let t = CGFloat(index) / CGFloat(Self.bristles - 1)
          let x = bodyEnd + tip * t
          // 越靠右越薄：高度从 7pt 收到 1.5pt，浓度从 1 收到 0.4。
          let shrink = 1 - 0.78 * t
          let jitter = 0.75 + 0.5 * noise(index)
          let barHeight = max(1.5, Self.bodyHeight * shrink * jitter)
          let alpha = (1 - 0.6 * t) * (0.75 + 0.25 * noise(index + 40))
          let barWidth = 0.9 + 0.7 * noise(index + 7)
          let rect = NSRect(
            x: x, y: midY - barHeight / 2, width: barWidth, height: barHeight)
          tint.withAlphaComponent(alpha).setFill()
          NSBezierPath(rect: rect).fill()
        }
      }
    }

    // 4) 暂停斜纹：45° 每 4pt 一条，覆在整条上。
    if paused {
      let hatch = NSBezierPath()
      var x: CGFloat = -height
      while x < width + height {
        hatch.move(to: NSPoint(x: x, y: height))
        hatch.line(to: NSPoint(x: x + height, y: 0))
        x += 4
      }
      hatch.lineWidth = 1
      paperLine.withAlphaComponent(0.42).setStroke()
      hatch.stroke()
    }
  }
}
