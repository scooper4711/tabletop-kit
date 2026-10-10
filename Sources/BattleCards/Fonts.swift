import CoreText
import Foundation
import SwiftUI

/// PostScript names of the fonts converted into `Generated/Fonts` by the import.
public enum FontName {
    public static let condensed = "RobotoCondensed-Regular"
    public static let condensedBold = "RobotoCondensed-Bold"
    public static let condensedItalic = "RobotoCondensed-Italic"
    public static let body = "Roboto-Regular"
    public static let bodyBold = "Roboto-Bold"
    public static let bodyItalic = "Roboto-Italic"
    public static let actions = "Pathfinder2eActions"
}

public enum Fonts {
    /// Registers every font in `Generated/Fonts` for this process. Missing fonts fall back to the system font.
    public static func register(from generatedDirectory: URL?) {
        guard let folder = generatedDirectory?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// A custom font that scales with Dynamic Type relative to the body style.
    public static func pad(_ name: String, size: CGFloat) -> Font {
        .custom(name, size: size, relativeTo: .body)
    }
}
