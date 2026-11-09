import SwiftUI

/// What a newly opened window shows before it has a document: a title, the app's symbol, one line saying what the
/// app does with a file, and the two ways in, Open… and Open from Scrollkeeper…, side by side. Pluck and Mapsmith
/// both start by opening a PDF, so one view keeps their empty windows alike.
///
/// The File menu has the same two commands with their shortcuts (⌘O and ⇧⌘O); the buttons carry none, so a key
/// press never reaches two commands.
public struct EmptyWindowView: View {
    private let title: String
    private let symbol: String
    private let message: String
    private let isDropTargeted: Bool
    private let open: () -> Void
    private let openFromScrollkeeper: () -> Void

    /// - Parameters:
    ///   - title: What the window asks for, such as "Open a PDF".
    ///   - symbol: The SF Symbol of the app.
    ///   - message: One line saying what the app does with the file and that it can be dropped.
    ///   - isDropTargeted: Whether a file is being dragged over the window, which outlines it.
    ///   - open: Asks the user for a file.
    ///   - openFromScrollkeeper: Opens the window that lists the user's Scrollkeeper library.
    public init(title: String, symbol: String, message: String, isDropTargeted: Bool = false,
                open: @escaping () -> Void, openFromScrollkeeper: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.message = message
        self.isDropTargeted = isDropTargeted
        self.open = open
        self.openFromScrollkeeper = openFromScrollkeeper
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            HStack {
                Button("Open…", action: open)
                Button("Open from Scrollkeeper…", action: openFromScrollkeeper)
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(8)
            }
        }
    }
}
