import ImageIO
import SwiftUI

/// A title's cover from Scrollkeeper's folder, or the app's symbol when there is none, loaded off the main thread.
public struct ScrollkeeperCoverThumbnail: View {
    private let url: URL?
    private let placeholderSymbol: String
    @State private var image: CGImage?

    /// `placeholderSymbol` is the SF Symbol shown for a title without a cover, such as "map".
    public init(url: URL?, placeholderSymbol: String) {
        self.url = url
        self.placeholderSymbol = placeholderSymbol
    }

    public var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else {
                Image(systemName: placeholderSymbol).foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 36)
        .task(id: url) {
            guard let url else { return }
            image = await Task.detached { Self.loadImage(url) }.value
        }
    }

    nonisolated static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
