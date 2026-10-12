import SwiftUI

/// A battle card the user can flip and show full screen. Tapping empty card area shows or hides the corner icons:
/// flip at the top right, full screen at the bottom right. With a pointer, each icon shows while the pointer is
/// over its corner. A pinch out opens full screen on the face that's showing. Reset its state with `.id(_:)`.
public struct InteractiveBattleCard<Front: View, Back: View>: View {
    let front: Front
    let back: Back
    let hasBack: Bool
    @State private var isFlipped = false
    @State private var isFullScreen: Bool
    @Environment(\.cardFullScreenHost) private var host
    @Environment(\.glossary) private var glossary
    @Environment(\.cardArt) private var cardArt
    @Environment(\.artPictureLoader) private var artLoader

    /// A card with a back to flip to, such as `CardBack` around the creature's `ArtPicture`.
    public init(@ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back) {
        self.init(front: front(), back: back(), hasBack: true)
    }

    /// `isFullScreen` starts the card full screen, for tests.
    init(front: Front, back: Back, hasBack: Bool, isFullScreen: Bool = false) {
        self.front = front
        self.back = back
        self.hasBack = hasBack
        _isFullScreen = State(initialValue: isFullScreen)
    }

    public var body: some View {
        CardFaces(front: front, back: back, hasBack: hasBack, isFlipped: $isFlipped,
                  fullScreenAction: .open { isFullScreen = true })
            .simultaneousGesture(MagnifyGesture().onEnded { value in
                if CardPinch.opens(value.magnification) { isFullScreen = true }
            })
            .onChange(of: isFullScreen, initial: true) { presentInHost() }
            .cardFullScreenCover(isPresented: isUsingCover ? $isFullScreen : .constant(false)) { fullScreen }
    }

    /// On the Mac, a host fills the window; elsewhere, or without a host, the card covers the screen.
    private var isUsingCover: Bool {
        #if os(macOS)
        host == nil
        #else
        true
        #endif
    }

    private var fullScreen: some View {
        FullScreenCard(front: front, back: back, hasBack: hasBack, isFlipped: $isFlipped) { isFullScreen = false }
    }

    /// The host is outside the card, so the card's environment goes with it.
    private func presentInHost() {
        guard !isUsingCover, let host else { return }
        host.content = isFullScreen
            ? AnyView(fullScreen.environment(\.glossary, glossary).environment(\.cardArt, cardArt)
                .environment(\.artPictureLoader, artLoader))
            : nil
    }
}

extension InteractiveBattleCard where Back == EmptyView {
    /// A card without a back, such as a player character's: it shows full screen but doesn't flip.
    public init(@ViewBuilder front: () -> Front) {
        self.init(front: front(), back: EmptyView(), hasBack: false)
    }
}

/// The card on black, filling the screen or window: the corner icon, a pinch in or Escape closes it.
struct FullScreenCard<Front: View, Back: View>: View {
    let front: Front
    let back: Back
    let hasBack: Bool
    @Binding var isFlipped: Bool
    let close: () -> Void

    var body: some View {
        CardFaces(front: front, back: back, hasBack: hasBack, isFlipped: $isFlipped, fullScreenAction: .close(close))
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .simultaneousGesture(MagnifyGesture().onEnded { value in
                if CardPinch.closes(value.magnification) { close() }
            })
            .background {
                Button("Exit Full Screen", action: close)
                    .keyboardShortcut(.cancelAction)
                    .hidden()
            }
    }
}

/// The card's two faces with the 3D flip and the corner icons.
struct CardFaces<Front: View, Back: View>: View {
    let front: Front
    let back: Back
    let hasBack: Bool
    @Binding var isFlipped: Bool
    let fullScreenAction: FullScreenAction
    @State private var controls: CardControls

    /// `controls` sets which icons show at first, for tests.
    init(front: Front, back: Back, hasBack: Bool, isFlipped: Binding<Bool>, fullScreenAction: FullScreenAction,
         controls: CardControls = CardControls()) {
        self.front = front
        self.back = back
        self.hasBack = hasBack
        _isFlipped = isFlipped
        self.fullScreenAction = fullScreenAction
        _controls = State(initialValue: controls)
    }

    var body: some View {
        ZStack {
            front.opacity(isFlipped ? 0 : 1)
            if hasBack && isFlipped {
                back.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { controls.showsIcons.toggle() } }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { controls.size = $0 }
        .onContinuousHover { phase in
            if case let .active(location) = phase { controls.hover(at: location) } else { controls.hover(at: nil) }
        }
        .overlay(alignment: .topTrailing) {
            if hasBack && controls.isShowing(.topTrailing) {
                CornerIcon(label: isFlipped ? "Show Stat Block" : "Flip Card",
                           systemImage: "arrow.triangle.2.circlepath") {
                    withAnimation(.easeInOut(duration: 0.45)) { isFlipped.toggle() }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if controls.isShowing(.bottomTrailing) {
                CornerIcon(label: fullScreenAction.label, systemImage: fullScreenAction.systemImage,
                           action: fullScreenAction.perform)
            }
        }
    }
}

/// Which corner icons show: all of them after a tap, or the one under the pointer.
struct CardControls {
    var showsIcons = false
    var hoveredCorner: CardCorner?
    var size = CGSize.zero

    mutating func hover(at location: CGPoint?) {
        hoveredCorner = location.flatMap { CardCorner(at: $0, in: size) }
    }

    func isShowing(_ corner: CardCorner) -> Bool {
        showsIcons || hoveredCorner == corner
    }
}

/// How far a pinch must go to open or close full screen.
enum CardPinch {
    static func opens(_ magnification: CGFloat) -> Bool { magnification > 1.2 }
    static func closes(_ magnification: CGFloat) -> Bool { magnification < 0.8 }
}

/// What the bottom-right icon does: open full screen from the card, or close it.
struct FullScreenAction {
    let label: String
    let systemImage: String
    let perform: () -> Void

    static func open(_ perform: @escaping () -> Void) -> FullScreenAction {
        FullScreenAction(label: "Full Screen", systemImage: "arrow.up.left.and.arrow.down.right", perform: perform)
    }

    static func close(_ perform: @escaping () -> Void) -> FullScreenAction {
        FullScreenAction(label: "Exit Full Screen", systemImage: "arrow.down.right.and.arrow.up.left",
                         perform: perform)
    }
}

/// The card corners that hold icons.
enum CardCorner {
    case topTrailing, bottomTrailing

    /// A corner is the last fifth of the card's width and the first or last fifth of its height.
    static let fraction: CGFloat = 0.2

    init?(at location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0, location.x >= size.width * (1 - Self.fraction) else { return nil }
        if location.y <= size.height * Self.fraction {
            self = .topTrailing
        } else if location.y >= size.height * (1 - Self.fraction) {
            self = .bottomTrailing
        } else {
            return nil
        }
    }
}

/// A round icon button in a card corner.
private struct CornerIcon: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.title2)
            .buttonStyle(.borderless)
            .padding(10)
            .background(.ultraThinMaterial, in: Circle())
            .padding(10)
            .help(label)
            .transition(.opacity)
    }
}
