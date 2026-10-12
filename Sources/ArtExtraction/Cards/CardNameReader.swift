import Foundation
import Vision

/// Reads an item's name off the front of a card printed as a picture: the title lines across the top, read with
/// Vision's text recognition.
enum CardNameReader {
    /// The part of the card, from the top, that holds the title.
    static let titleHeight = 0.2
    /// A line belongs to the title when it is at least this tall relative to the tallest line found there, and
    /// largely in capitals, as titles are printed (text recognition gets the case of many letters wrong:
    /// "BLowgUn"). On the Weapons & Armor deck, title lines measure 0.92 of the tallest, the description's first
    /// line about 0.7, and descriptions hold about a tenth capitals.
    static let titleLineShare = 0.6
    static let capitalsShare = 0.3

    /// The name in title case; empty when none can be read.
    static func name(onFront url: URL) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.regionOfInterest = CGRect(x: 0, y: 1 - titleHeight, width: 1, height: titleHeight)
        do {
            try VNImageRequestHandler(url: url).perform([request])
        } catch {
            return ""
        }
        return name(in: (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { (text: $0.string, box: observation.boundingBox) }
        })
    }

    /// The title from the lines found: the tallest ones in capitals, top to bottom, joined and title-cased.
    static func name(in lines: [(text: String, box: CGRect)]) -> String {
        let titled = lines.filter { isMostlyCapitals($0.text) }
        guard let tallest = titled.map(\.box.height).max() else { return "" }
        let words = titled.filter { $0.box.height >= tallest * titleLineShare }
            .sorted { $0.box.maxY > $1.box.maxY }
            .flatMap { $0.text.split(whereSeparator: \.isWhitespace).map(String.init) }
        return PawnLabel.titleCase(words)
    }

    private static func isMostlyCapitals(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        let capitals = Double(letters.filter(\.isUppercase).count)
        return !letters.isEmpty && capitals >= Double(letters.count) * capitalsShare
    }
}
