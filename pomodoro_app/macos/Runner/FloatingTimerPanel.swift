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
///
/// 两种显示模式（`pine.overlayStyle`，默认 `numeric` ＝原有观感，升级不打扰）：
/// - `numeric` 数字模式：阶段色点 + 阶段短标签 + 等宽大数字 + 底部细进度条，宽度随内容自适应；
/// - `progress` 进度模式：无任何数字，整只胶囊就是水位槽（见 `TideCapsuleView`），尺寸固定。
/// 两模式的毛玻璃外壳、置顶行为、拖拽/点击/右键、位置持久化完全一致。
final class FloatingTimerPanel: NSPanel {
  static let shared = FloatingTimerPanel()

  /// 胶囊显示模式。
  enum CapsuleStyle: String {
    case numeric
    case progress
  }

  /// 点击（未拖动）时的动作，由持有通道的窗口注入。
  var onClick: (() -> Void)?
  /// 右键菜单动作回传，取值与菜单栏一致：toggle / complete / discard。
  var onAction: ((String) -> Void)?

  private static let enabledKey = "pine.overlayEnabled"
  private static let originKey = "pine.overlayOrigin"
  private static let styleKey = "pine.overlayStyle"

  /// 数字模式的基准尺寸（宽度随后由 `fitWidth` 按内容实测校正）。
  private static let numericSize = NSSize(width: 190, height: 48)

  /// Dart 在暂停时推送的阶段词。进度模式没有文字，靠它判断「浪要不要冻结」。
  private static let pausedPhase = "已暂停"

  // 数字模式内容（进度模式下整体隐藏而不拆除，切回来即用）。
  private let dotView = NSView()
  private let phaseLabel = NSTextField(labelWithString: "专注中")
  private let timeLabel = NSTextField(labelWithString: "00:00")
  private let progressView = PineProgressView()
  private let numericStack = NSStackView()

  // 进度模式内容。
  private let tideView = TideCapsuleView()

  private var effectView = NSVisualEffectView()

  private var lastPhase: String?
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

  /// 当前显示模式。
  var style: CapsuleStyle {
    get {
      CapsuleStyle(rawValue: UserDefaults.standard.string(forKey: Self.styleKey) ?? "")
        ?? .numeric
    }
    set {
      guard newValue != style else { return }
      UserDefaults.standard.set(newValue.rawValue, forKey: Self.styleKey)
      applyStyle()
    }
  }

  /// 供菜单栏在 `menuWillOpen` 时勾选当前模式。
  func currentStyle() -> CapsuleStyle { style }

  private static func storedStyle() -> CapsuleStyle {
    CapsuleStyle(rawValue: UserDefaults.standard.string(forKey: styleKey) ?? "") ?? .numeric
  }

  /// 首次摆放/恢复位置时的基准尺寸（数字模式宽度随后会被 `fitWidth` 修正）。
  private var restoreSize: NSSize {
    style == .progress ? TideCapsuleView.size : Self.numericSize
  }

  private init() {
    let initialSize =
      Self.storedStyle() == .progress ? TideCapsuleView.size : Self.numericSize
    super.init(
      contentRect: NSRect(origin: .zero, size: initialSize),
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

    let root = PineDragView(frame: NSRect(origin: .zero, size: initialSize))
    root.onClick = { [weak self] in self?.onClick?() }
    let effect = NSVisualEffectView(frame: root.bounds)
    effect.autoresizingMask = [.width, .height]
    effect.material = .hudWindow
    effect.blendingMode = .behindWindow
    effect.state = .active
    effect.wantsLayer = true
    // 胶囊：圆角取半高；1px 白色细边让它在浅色壁纸上也有轮廓。
    effect.layer?.cornerRadius = initialSize.height / 2
    effect.layer?.masksToBounds = true
    effect.layer?.borderWidth = 1
    effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
    root.addSubview(effect)
    effectView = effect
    contentView = root

    // 数字模式（V3 信息型）：阶段色点 + 阶段短标签 + 右对齐大数字 + 底部细进度。
    dotView.wantsLayer = true
    dotView.layer?.cornerRadius = 4
    dotView.layer?.backgroundColor =
      NSColor.white.withAlphaComponent(0.5).cgColor

    phaseLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
    phaseLabel.textColor = NSColor.white.withAlphaComponent(0.72)
    phaseLabel.lineBreakMode = .byTruncatingTail
    // 不做弹性拉伸：宽度由内容实测决定（fitWidth），保证左右留白恒等。
    phaseLabel.setContentHuggingPriority(.required, for: .horizontal)
    phaseLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    timeLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
    timeLabel.textColor = .white
    timeLabel.alignment = .right
    timeLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    for view in [dotView, phaseLabel, timeLabel] {
      numericStack.addArrangedSubview(view)
    }
    numericStack.orientation = .horizontal
    numericStack.alignment = .centerY
    numericStack.spacing = 8
    numericStack.translatesAutoresizingMaskIntoConstraints = false
    effect.addSubview(numericStack)
    progressView.translatesAutoresizingMaskIntoConstraints = false
    effect.addSubview(progressView)

    NSLayoutConstraint.activate([
      dotView.widthAnchor.constraint(equalToConstant: 8),
      dotView.heightAnchor.constraint(equalToConstant: 8),
      numericStack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
      numericStack.centerYAnchor.constraint(equalTo: effect.centerYAnchor, constant: -4),
      // 右侧只设下限，宽度由 fitWidth 按内容伸缩决定。
      numericStack.trailingAnchor.constraint(
        lessThanOrEqualTo: effect.trailingAnchor, constant: -16),
      progressView.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
      progressView.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
      progressView.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -7),
      progressView.heightAnchor.constraint(equalToConstant: 3),
    ])

    // 进度模式内容：铺满整只胶囊（外壳的圆角负责裁齐）。
    tideView.frame = effect.bounds
    tideView.autoresizingMask = [.width, .height]
    effect.addSubview(tideView)

    applyStyle(animated: false)
  }

  /// 切换模式：换内容、换尺寸、换圆角。右缘锚定、向左伸缩，不改动用户摆好的位置关系。
  private func applyStyle(animated: Bool = true) {
    let progressMode = style == .progress
    numericStack.isHidden = progressMode
    progressView.isHidden = progressMode
    tideView.isHidden = !progressMode

    let target = progressMode ? TideCapsuleView.size : Self.numericSize
    if abs(frame.width - target.width) > 0.5 || abs(frame.height - target.height) > 0.5 {
      var next = frame
      let rightEdge = frame.origin.x + frame.width
      next.size = target
      next.origin.x = rightEdge - target.width
      setFrame(next, display: true, animate: animated && isVisible)
    }
    // 圆角恒取半高：两模式高度不同，必须随尺寸刷新。
    effectView.layer?.cornerRadius = frame.height / 2
  }

  /// 内容实测宽度 → 窗口随文字伸缩，左右留白恒等 16/16、右缘锚定。
  /// 位数跨档（如 25:00 → 01:23:45）时才改宽度，并用系统动画平滑过渡。
  /// 仅数字模式使用：进度模式尺寸固定，本来就没有位数跨档问题。
  private func fitWidth(animated: Bool) {
    guard style == .numeric else { return }
    let hasPhase = !phaseLabel.stringValue.isEmpty
    let dotPart: CGFloat = hasPhase ? 8 + 8 : 0            // 圆点 + 间距
    let phasePart: CGFloat = hasPhase
      ? ceil(phaseLabel.intrinsicContentSize.width) + 8     // 标签 + 与数字间距
      : 0
    let timePart = ceil(timeLabel.intrinsicContentSize.width)
    let width = 16 + dotPart + phasePart + timePart + 16
    guard abs(width - frame.width) > 0.5 else { return }
    var target = frame
    let rightEdge = frame.origin.x + frame.width
    target.size.width = width
    target.origin.x = rightEdge - width
    setFrame(target, display: true, animate: animated && isVisible)
  }

  /// 每秒一次的刷新入口。`active` 为 false（无进行中会话）时自动隐藏。
  func apply(
    head: String, phase: String, elapsed: String, progress: Double,
    over: Double, tintArgb: Int, active: Bool
  ) {
    if style == .progress {
      // 进度模式：只用「进度 + 溢出 + 配色」。阶段文字没有位置显示，但要拿它判暂停——
      // Dart 在暂停时推 `已暂停` 并把 tint 换成中性灰（与菜单栏文字一致），
      // 于是「浪冻结 + 中性配色」两个信号同时到位。
      tideView.update(
        progress: progress,
        over: over,
        tint: pineColor(tintArgb),
        animated: phase != Self.pausedPhase)
      setVisible(userEnabled && active)
      return
    }

    if phase != lastPhase {
      lastPhase = phase
      // 阶段词为空（理论上仅空闲瞬间）时收起点与标签，让宽度只按时间算。
      let hasPhase = !phase.isEmpty
      dotView.isHidden = !hasPhase
      phaseLabel.isHidden = !hasPhase
      if hasPhase { phaseLabel.stringValue = phase }
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
      // 阶段色只做「点 + 进度」，数字保持白色——更接近 macOS 小件的克制观感。
      dotView.layer?.backgroundColor = tint.cgColor
      progressView.tint = tint
      lastTint = tintArgb
    }
    setVisible(userEnabled && active)
    // 内容宽度随文字伸缩（左右留白恒等），位数跨档时平滑过渡。
    fitWidth(animated: true)
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
    let size = restoreSize
    if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
      let parts = saved.split(separator: ",").compactMap { Double($0) }
      if parts.count == 2, let screen = NSScreen.screens.first(where: {
        $0.frame.contains(NSPoint(x: parts[0], y: parts[1]))
      }) ?? NSScreen.main {
        let rect = NSRect(
          x: parts[0], y: parts[1],
          width: size.width, height: size.height)
        // 换显示器/改分辨率后旧坐标可能跑出屏幕，越界就回退到默认位置。
        if screen.visibleFrame.insetBy(dx: -40, dy: -40).contains(rect) {
          setFrame(
            NSRect(origin: NSPoint(x: parts[0], y: parts[1]), size: size),
            display: true)
          return
        }
      }
    }
    guard let screen = NSScreen.main else { return }
    let visible = screen.visibleFrame
    setFrameOrigin(NSPoint(
      x: visible.maxX - size.width - 14,
      y: visible.maxY - size.height - 6))
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
      title: "打开 pinecore", action: #selector(openMainWindow), keyEquivalent: "")
    open.target = self
    menu.addItem(open)
    let styleItem = NSMenuItem(title: "显示模式", action: nil, keyEquivalent: "")
    styleItem.submenu = styleSubmenu()
    menu.addItem(styleItem)
    let hide = NSMenuItem(
      title: "隐藏悬浮计时器", action: #selector(hideSelf), keyEquivalent: "")
    hide.target = self
    menu.addItem(hide)
    menu.popUp(positioning: nil, at: point, in: contentView)
  }

  /// 「显示模式 ▸ 数字 / 进度」子菜单。右键菜单与菜单栏共用同一套构造逻辑，
  /// 保证两处入口的文案与勾选状态永远一致（菜单栏每次展开重建它）。
  func styleSubmenu() -> NSMenu {
    let sub = NSMenu()
    sub.autoenablesItems = false
    for (title, value) in [("数字", CapsuleStyle.numeric), ("进度", CapsuleStyle.progress)] {
      let entry = NSMenuItem(
        title: title, action: #selector(handleStyleAction(_:)), keyEquivalent: "")
      entry.target = self
      entry.representedObject = value.rawValue
      entry.state = value == style ? .on : .off
      sub.addItem(entry)
    }
    return sub
  }

  @objc private func handleAction(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    onAction?(id)
  }

  @objc private func handleStyleAction(_ sender: NSMenuItem) {
    guard let raw = sender.representedObject as? String,
          let next = CapsuleStyle(rawValue: raw) else { return }
    style = next
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

/// 悬浮窗底部进度条，随阶段配色（数字模式用）。
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

/// 进度模式「潮汐」：整只胶囊就是水位槽，前缘是一道竖直正弦浪，浪前还有一条更浅的
/// 「前滩」湿痕——于是读起来是水在推进，而不是色块在变长。
///
/// 涨满之后靠**泡沫痕**继续表达：水位封顶在 100%，再往上没有位置可涨，
/// 于是叠一条更亮的金（白 32%）从左推进，长度 = 溢出比例（满 = 又干满一整轮）。
/// 超过一轮不再增长（不假装能表示无限），精确量由菜单栏文字承担。
///
/// - 浪的摆动交给 Core Animation（`position.x` 往复 ±amplitude / 3.2s），不占 CPU，
///   也不需要在原生侧另起一个计时器；
/// - 暂停时移除动画 → 浪冻结（配合 Dart 推送的中性灰 tint，两个信号同时到位）；
/// - 超时不做常驻呼吸，只在「刚涨满」那一下脉冲 3 次后静止；
/// - 两处动效都遵守系统「减弱动态效果」。
///
/// 与外壳的分工：毛玻璃 + 半高圆角 + 1px 白描边由 `FloatingTimerPanel` 提供，
/// 本视图只画「槽 → 前滩 → 液面 → 泡沫痕」，并把它们裁进圆角胶囊。
///
/// 纯 Cocoa 无 Flutter 依赖，可单独编译渲染（见 `outputs/` 下的落地核对图）。
final class TideCapsuleView: NSView {
  /// 进度模式的固定尺寸（这也是它比数字模式安静的原因之一：不再随内容伸缩）。
  static let size = NSSize(width: 140, height: 28)

  /// 左侧溢出：浪左右摆动时也露不到左边缘。
  private static let bleed: CGFloat = 12
  /// 前滩湿痕超前主液面的距离。
  private static let shallowAhead: CGFloat = 8

  private static let waveKey = "pine.tide.wave"
  private static let scrollKey = "pine.tide.scroll"
  private static let pulseKey = "pine.tide.pulse"

  /// 浪的振幅（曲线峰值；二次贝塞尔峰值 ≈ 控制点偏移的一半）。
  private static let amplitude: CGFloat = 2.6
  /// 单个二次贝塞尔段的垂直跨度（＝半个波长）。
  private static let halfWave: CGFloat = 7
  /// 一个波长：波形每平移这一段就与自身重合，所以垂直滚浪可以无缝循环。
  private static let wavelength: CGFloat = halfWave * 2
  /// 水平摆动单程时长（往复一个完整呼吸＝它的两倍）。
  private static let swayDuration: CFTimeInterval = 4.6
  /// 垂直滚浪走完一个波长的时长。与摆动周期（9.2s）不成整数比，
  /// 两者合成的观感周期约 15.6s，因此不会显出机械重复。
  private static let scrollDuration: CFTimeInterval = 3.4
  /// 摆动缓动：正弦式两端缓、中段快，比线性更接近呼吸。
  private static let swayCurve = CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1)

  private let trackLayer = CAShapeLayer()
  private let shallowLayer = CAShapeLayer()
  private let liquidLayer = CAShapeLayer()
  /// 泡沫痕：涨满后叠在满潮之上的第二道潮，长度＝溢出比例。
  private let foamLayer = CAShapeLayer()
  private let maskLayer = CAShapeLayer()

  private var progress: Double = 0
  /// 溢出比例 0…1（1 ＝ 又干满一整轮）。超过一轮不再增长，精确量交给菜单栏文字。
  private var over: Double = 0
  private var tint: NSColor = .white
  private var waveEnabled = true
  private var waveOn = false
  private var foamWaveOn = false
  /// 本轮「刚跨过计划时长」待播的一次性提示（播完即清）。
  private var pulsePending = false
  /// 本轮是否见过「未涨满」。用来把提示严格限定为「本轮内跨过」，
  /// 避免 App 在会话早已超时后才启动时误报一次。
  private var seenBelowFull = false

  /// 系统「减弱动态效果」。App 的 Flutter 侧已有同等判断，原生侧不能漏。
  /// 每秒刷新都会重读，用户在系统设置里改了立即生效，不需要额外监听。
  private var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = false

    // 槽 10% / 前滩 20%：前滩必须比干槽更亮才是「打湿的水痕」。
    // （设计稿里前滩给的是 10%、比槽 12% 还暗，叠在 HUD 底色上两者差不到 2/255，
    //   等于白画——落地时把两者的明暗关系反过来。）
    trackLayer.fillColor = NSColor.white.withAlphaComponent(0.10).cgColor
    shallowLayer.fillColor = NSColor.white.withAlphaComponent(0.20).cgColor
    liquidLayer.fillColor = tint.cgColor
    // 泡沫痕：白 32% 叠在满潮（金）之上 ≈ #E6C382，比底色亮一档但仍是金系，
    // 读作「潮水漫过留下的泡沫痕」而不是另起一种颜色。
    // （22% 实测对满金的亮度差只有 7.4%，远看会漏；32% 提到约 11.6%。）
    foamLayer.fillColor = NSColor.white.withAlphaComponent(0.32).cgColor
    foamLayer.isHidden = true
    for shape in [trackLayer, shallowLayer, liquidLayer, foamLayer] {
      shape.masksToBounds = false
      layer?.addSublayer(shape)
    }
    // 裁剪：三者都不得越出胶囊。
    layer?.mask = maskLayer
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  /// 每秒一次的刷新入口：进度、溢出、配色，以及浪要不要动。
  func update(progress: Double, over: Double, tint: NSColor, animated: Bool) {
    let clamped = min(max(progress, 0), 1)
    // 只在「本轮第一次涨满」的那一下记一次一次性提示：刚跨过计划时长是有时效的事件，
    // 值得区别于「已经超时很久」——所以不做常驻呼吸（常驻置顶窗不该有无限动效）。
    if clamped < 1 {
      seenBelowFull = true
    } else if seenBelowFull {
      seenBelowFull = false
      pulsePending = true
    }
    self.progress = clamped
    self.over = min(max(over, 0), 1)
    self.tint = tint
    self.waveEnabled = animated
    // 每秒刷新不能走隐式动画：否则 path / fillColor 会被 Core Animation 补间出
    // 0.25s 的拖尾，和显式的浪动画叠在一起会糊成一团。
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    rebuild()
    CATransaction.commit()
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    rebuild()
    CATransaction.commit()
  }

  /// 重算槽、前滩、液面、泡沫痕四条路径，并同步动画状态。
  private func rebuild() {
    let box = bounds
    guard box.width > 1, box.height > 1 else { return }
    let capsule = CGPath(
      roundedRect: box,
      cornerWidth: box.height / 2,
      cornerHeight: box.height / 2,
      transform: nil)

    maskLayer.frame = box
    maskLayer.path = capsule
    trackLayer.frame = box
    trackLayer.path = capsule

    let front = box.width * CGFloat(progress)
    let full = front >= box.width - 0.5
    let empty = front <= 0.5

    shallowLayer.frame = box
    shallowLayer.path = wavePath(frontX: front + Self.shallowAhead)
    // 涨满时藏起前滩，否则右缘会留一道浅色水痕。
    shallowLayer.isHidden = empty || full

    liquidLayer.frame = box
    liquidLayer.path = wavePath(frontX: front)
    liquidLayer.fillColor = tint.cgColor
    liquidLayer.isHidden = empty

    // 泡沫痕：只在涨满后出现，长度＝溢出比例（1 ＝ 又干满一整轮）。
    // 它是进度模式里唯一表达「超时了多少」的东西——水位本身封顶在 100%。
    let foamVisible = full && over > 0.002
    foamLayer.frame = box
    foamLayer.path = wavePath(frontX: box.width * CGFloat(over))
    foamLayer.isHidden = !foamVisible

    // 浪：只在「正在推进」时摆——静止态不占用任何动画资源。
    // 系统开了「减弱动态效果」就一律不摆，信息（水位位置）完全不受影响。
    setWave(&waveOn, layers: [liquidLayer, shallowLayer],
            on: waveEnabled && !full && !empty && !reduceMotion)
    // 泡沫痕是第二道潮，自己推进时同样要摆；涨满后前缘被裁掉，无需再摆。
    setWave(&foamWaveOn, layers: [foamLayer],
            on: waveEnabled && foamVisible && over < 0.998 && !reduceMotion)

    // 超时：不是常驻呼吸，而是「刚涨满」那一刻的 3 次脉冲（约 3.6s）后归于静止。
    // 到点提醒本身已由系统通知 + 提示音承担，胶囊只负责别让这一下被漏看。
    if pulsePending {
      pulsePending = false
      liquidLayer.removeAnimation(forKey: Self.pulseKey)
      if !reduceMotion {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.72
        anim.duration = 0.6
        anim.autoreverses = true
        anim.repeatCount = 3
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        liquidLayer.add(anim, forKey: Self.pulseKey)
      }
    }
  }

  /// 按需开关一组「潮线」图层的动效。两组动画叠加，才是「水是活的」：
  ///
  /// 1. **水平摆动**（`position.x`，±amplitude，正弦缓动，往复）——潮位轻轻吞吐；
  /// 2. **垂直滚浪**（`position.y`，正好一个波长，线性，单向循环）——波峰沿着前缘
  ///    向一侧流动。这是"活水"感的主要来源；单个波长保证循环点与起点重合，看不出接缝。
  ///
  /// 用状态位去重：每秒刷新若直接 remove + add，动画会每秒从头开始，浪会一跳一跳。
  /// 各图层错开相位，三条前缘（主潮 / 前滩 / 泡沫）不同步，水才不是整块平移。
  private func setWave(_ state: inout Bool, layers: [CAShapeLayer], on: Bool) {
    guard on != state else { return }
    state = on
    for shape in layers {
      shape.removeAnimation(forKey: Self.waveKey)
      shape.removeAnimation(forKey: Self.scrollKey)
      guard on else { continue }

      // 相位错开：主潮为基准，前滩与泡沫各差半拍以上。
      let stagger: CFTimeInterval = shape === liquidLayer ? 0 : (shape === shallowLayer ? 0.6 : 1.1)

      let sway = CABasicAnimation(keyPath: "position.x")
      sway.fromValue = shape.position.x - Self.amplitude
      sway.toValue = shape.position.x + Self.amplitude
      sway.duration = Self.swayDuration
      sway.autoreverses = true
      sway.repeatCount = .infinity
      sway.timingFunction = Self.swayCurve
      sway.timeOffset = stagger
      shape.add(sway, forKey: Self.waveKey)

      let scroll = CABasicAnimation(keyPath: "position.y")
      scroll.fromValue = shape.position.y
      scroll.toValue = shape.position.y + Self.wavelength
      scroll.duration = Self.scrollDuration
      scroll.repeatCount = .infinity
      scroll.timingFunction = CAMediaTimingFunction(name: .linear)
      scroll.timeOffset = stagger * 0.7
      shape.add(scroll, forKey: Self.scrollKey)
    }
  }

  /// 液面路径：从左溢出边缘到 [frontX] 的实心区，右缘是一条竖直正弦浪。
  ///
  /// 波形上下各多画一个半波长以上（总跨度居中于胶囊）：垂直滚浪把整段波形平移
  /// 一个波长时，胶囊上下缘始终被覆盖，不会露出缝隙。
  private func wavePath(frontX: CGFloat) -> CGPath {
    let h = bounds.height
    let step = Self.halfWave                       // 半波的垂直跨度
    // 胶囊高度内的半波数 + 上下各一个波长（4 个半波）
    let base = max(2, Int((h / step).rounded()))
    let count = base + 6
    let span = step * CGFloat(count)
    let top = (h - span) / 2                       // 居中：上下溢出相等

    let path = CGMutablePath()
    path.move(to: CGPoint(x: -Self.bleed, y: top))
    path.addLine(to: CGPoint(x: frontX, y: top))
    var y = top
    var direction: CGFloat = 1
    for _ in 0..<count {
      path.addQuadCurve(
        to: CGPoint(x: frontX, y: y + step),
        control: CGPoint(x: frontX + direction * Self.amplitude * 2, y: y + step / 2))
      y += step
      direction = -direction
    }
    path.addLine(to: CGPoint(x: -Self.bleed, y: top + span))
    path.closeSubpath()
    return path
  }
}
