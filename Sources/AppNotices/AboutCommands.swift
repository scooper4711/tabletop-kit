import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Replaces the app menu's About item: on the Mac with the standard About panel, its credits carrying Paizo's
/// notices; on the iPad with `AboutWindow`, since the item's default there opens an empty window.
public struct AboutCommands: Commands {
    private let info: AboutInfo

    public init(info: AboutInfo) {
        self.info = info
    }

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            #if os(macOS)
            Button("About \(info.appName)") { AboutPanel.show(info) }
            #else
            AboutWindowButton(appName: info.appName)
            #endif
        }
    }
}

#if os(macOS)
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
#else
/// The About screen in a window of its own, which the menu bar's About item opens (`AboutCommands`). Add it after
/// the app's own scenes, so the app still opens on its own window. It takes no links or files, which still reach
/// the app's windows.
public struct AboutWindow: Scene {
    public static let id = "about"
    private let info: AboutInfo

    public init(info: AboutInfo) {
        self.info = info
    }

    public var body: some Scene {
        WindowGroup("About \(info.appName)", id: Self.id) {
            AboutWindowContent(info: info)
        }
        .handlesExternalEvents(matching: [])
    }
}

/// Opens the About window; a view of its own, since `openWindow` is read from a view's environment.
private struct AboutWindowButton: View {
    let appName: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About \(appName)") { openWindow(id: AboutWindow.id) }
    }
}

/// `AboutView` with a Done button that closes its window.
private struct AboutWindowContent: View {
    let info: AboutInfo
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        NavigationStack {
            AboutView(info: info)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismissWindow(id: AboutWindow.id) }
                    }
                }
        }
    }
}
#endif
