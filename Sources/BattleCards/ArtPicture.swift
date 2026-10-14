import CoreGraphics
import SwiftUI

/// Loads a creature's art at full size from wherever the app keeps it: Turnkeeper's art store, Field Guide's art
/// model. Set it as the `artPictureLoader` environment value.
public struct ArtPictureLoader: Sendable {
    let load: @Sendable (String) async -> CGImage?

    public init(_ load: @escaping @Sendable (String) async -> CGImage?) {
        self.load = load
    }

    /// Loads nothing, for previews and before the app sets one.
    public static let none = ArtPictureLoader { _ in nil }
}

extension EnvironmentValues {
    @Entry public var artPictureLoader = ArtPictureLoader.none
}

/// A creature's art at full size, fitted to the space, with a spinner while it loads. A card back's art.
public struct ArtPicture: View {
    let path: String
    @Environment(\.artPictureLoader) private var loader
    @State private var image: CGImage?
    @State private var isLoading = true

    /// `path` is what the app's loader takes, such as an art library ID or a file inside `Generated`.
    public init(path: String) {
        self.path = path
    }

    public var body: some View {
        Group {
            if let image {
                // Smooth scaling: a small token's art may be enlarged.
                Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
            } else if isLoading {
                ProgressView()
            }
        }
        .task(id: path) {
            isLoading = true
            image = await loader.load(path)
            isLoading = false
        }
    }
}
