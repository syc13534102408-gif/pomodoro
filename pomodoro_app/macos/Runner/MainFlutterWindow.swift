import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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

    super.awakeFromNib()
  }
}
