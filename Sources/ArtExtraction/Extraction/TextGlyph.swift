import CoreGraphics
import Foundation

/// Text shown by one text-showing operator, at the point where it starts.
struct TextGlyph: Equatable {
    let text: String
    /// Where the text starts, in page space.
    let origin: CGPoint
    /// The type's height on the page, in points; zero when unknown.
    var fontSize: CGFloat = 0
    /// The direction the text runs, in radians counterclockwise from the page's x axis.
    var angle: CGFloat = 0
}

/// The text matrices of a content stream's text objects, enough to place each piece of text shown. Text
/// following other text in the same operator, or moved by `T*`, is placed where the operator starts.
struct TextState {
    private var textMatrix = CGAffineTransform.identity
    private var lineMatrix = CGAffineTransform.identity
    /// Reads the current font's bytes; set by `Tf`.
    var decoder = FontDecoder.plain
    /// The size `Tf` sets, in text space.
    var fontSize: CGFloat = 0

    /// `BT`: a text object starts at the origin.
    mutating func begin() {
        textMatrix = .identity
        lineMatrix = .identity
    }

    /// `Tm`.
    mutating func setMatrix(_ matrix: CGAffineTransform) {
        textMatrix = matrix
        lineMatrix = matrix
    }

    /// `Td` and `TD`: the next line starts `offset` from the start of this one.
    mutating func moveLine(by offset: CGPoint) {
        lineMatrix = CGAffineTransform(translationX: offset.x, y: offset.y).concatenating(lineMatrix)
        textMatrix = lineMatrix
    }

    /// The text placed on the page through the current transformation matrix.
    func glyph(_ text: String, transform: CGAffineTransform) -> TextGlyph {
        let matrix = textMatrix.concatenating(transform)
        return TextGlyph(text: text, origin: CGPoint.zero.applying(matrix),
                         fontSize: fontSize * (matrix.c * matrix.c + matrix.d * matrix.d).squareRoot(),
                         angle: atan2(matrix.b, matrix.a))
    }

    /// The string operand of `Tj`, `'` and `"`, as text.
    func popString(_ scanner: CGPDFScannerRef) -> String {
        var string: CGPDFStringRef?
        guard CGPDFScannerPopString(scanner, &string), let string else { return "" }
        return decoder.text(of: string)
    }

    /// The strings of `TJ`'s array as text, joined; the spacing numbers between them are skipped.
    func popArray(_ scanner: CGPDFScannerRef) -> String {
        var array: CGPDFArrayRef?
        guard CGPDFScannerPopArray(scanner, &array), let array else { return "" }
        return (0..<CGPDFArrayGetCount(array)).map { index -> String in
            var string: CGPDFStringRef?
            guard CGPDFArrayGetString(array, index, &string), let string else { return "" }
            return decoder.text(of: string)
        }.joined()
    }
}
