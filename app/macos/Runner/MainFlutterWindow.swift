import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Comfortable desktop default; user can resize.
    let size = NSSize(width: 1100, height: 760)
    self.setContentSize(size)
    self.minSize = NSSize(width: 880, height: 600)
    self.title = "Vitalog"
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    VisionOcrPlugin.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
