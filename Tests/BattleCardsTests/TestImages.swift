import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A square PNG of one color.
func writePNG(side: Int, to url: URL) throws {
    guard let image = squareImage(side: side),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

/// A square image of one color.
func squareImage(side: Int) -> CGImage? {
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    context?.setFillColor(CGColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 1))
    context?.fill(CGRect(x: 0, y: 0, width: side, height: side))
    return context?.makeImage()
}

#if os(macOS)
import AppKit
import SwiftUI

/// Shows a view in an offscreen window long enough for its tasks to run.
@MainActor
func showInWindow(_ view: some View, size: CGSize = CGSize(width: 300, height: 400)) async throws -> NSWindow {
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
                          backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    window.contentView?.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(200))
    return window
}
#endif
