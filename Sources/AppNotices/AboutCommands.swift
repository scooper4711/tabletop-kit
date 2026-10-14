#if os(macOS)
import AppKit
import SwiftUI

/// Replaces the app menu's About item with the standard About panel, its credits carrying Paizo's notices.
public struct AboutCommands: Commands {
    private let info: AboutInfo

    public init(info: AboutInfo) {
        self.info = info
    }

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(info.appName)") { AboutPanel.show(info) }
        }
    }
}

/// The standard About panel with `AboutInfo.panelText` as its credits.
public enum AboutPanel {
    @MainActor
    public static func show(_ info: AboutInfo) {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits(for: info)])
        NSApplication.shared.activate()
    }

    static func credits(for info: AboutInfo) -> NSAttributedString {
        NSAttributedString(string: info.panelText, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor
        ])
    }
}
#endif
