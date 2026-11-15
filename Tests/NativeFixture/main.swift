import AppKit

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
let fixtureName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "BF"
item.button?.title = fixtureName.split(separator: " ").last?.first.map(String.init) ?? "T"
item.button?.setAccessibilityIdentifier("BarFoldTestItem")
application.run()
