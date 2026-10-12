import Observation
import SwiftUI

/// Where a Mac window shows a card full screen: an overlay that fills the window, over everything in it.
@MainActor @Observable
final class CardFullScreenHost {
    var content: AnyView?
}

extension EnvironmentValues {
    @Entry var cardFullScreenHost: CardFullScreenHost?
}

extension View {
    /// Lets the interactive cards inside show full screen over this view, which should fill its window. Apply it
    /// to each window's root view, and to sheets' roots so their cards fill the sheet. Needed on the Mac only:
    /// elsewhere, cards cover the screen.
    public func battleCardFullScreenHost() -> some View {
        modifier(CardFullScreenHostModifier())
    }

    /// A cover over the whole screen on iOS; on the Mac, without a host, a large sheet.
    @ViewBuilder
    func cardFullScreenCover(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> some View)
        -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented) { content().frame(minWidth: 800, minHeight: 900) }
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }
}

private struct CardFullScreenHostModifier: ViewModifier {
    @State private var host = CardFullScreenHost()

    func body(content: Content) -> some View {
        content
            .environment(\.cardFullScreenHost, host)
            .overlay {
                if let card = host.content {
                    card.transition(.opacity).ignoresSafeArea()
                }
            }
            .animation(.easeInOut(duration: 0.25), value: host.content == nil)
    }
}
