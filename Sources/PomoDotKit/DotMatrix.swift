import Foundation

/// A 5x7 dot-matrix glyph table, in the lineage of 1980s IBM mainframe dot-matrix
/// displays — the same lineage Nothing's NDot typeface draws from.
///
/// Deliberately NOT a bundled font file. Drawing the grid ourselves is licence-clean
/// and, more importantly, lets us render the *unlit* dots too. A font can only give us
/// the lit ones, and the unlit grid is the whole visual signature of a matrix display.
/// It also does real work: the dim grid is a local scrim that keeps the lit dots legible
/// over clear glass, which is why this app can be as transparent as it is. (ISA § Criteria
/// ISC-22..26.)
public enum DotMatrix {

    /// Rows are top-to-bottom, each string is left-to-right, `#` is a lit dot.
    /// Width is per-glyph so the colon can be narrow rather than padded to 5.
    public struct Glyph: Sendable {
        public let width: Int
        public let rows: [[Bool]]

        init(_ pattern: [String]) {
            // Local, not `self.width`: referencing a property inside the closure would
            // capture a partially-initialised `self`.
            let glyphWidth = pattern.map(\.count).max() ?? 0
            self.width = glyphWidth
            self.rows = pattern.map { row in
                var bits = row.map { $0 == "#" }
                // Pad short rows so every row is `glyphWidth` long.
                while bits.count < glyphWidth { bits.append(false) }
                return bits
            }
        }

        /// Lit-dot coordinates as (column, row) pairs.
        public var litDots: [(x: Int, y: Int)] {
            rows.enumerated().flatMap { y, row in
                row.enumerated().compactMap { x, on in on ? (x: x, y: y) : nil }
            }
        }
    }

    /// Every glyph is 7 rows tall. Digits are 5 wide; the colon is 1 wide.
    public static let height = 7

    public static let digits: [Glyph] = [
        Glyph([" ### ",   // 0
               "#   #",
               "#  ##",
               "# # #",
               "##  #",
               "#   #",
               " ### "]),
        Glyph(["  #  ",   // 1
               " ##  ",
               "  #  ",
               "  #  ",
               "  #  ",
               "  #  ",
               " ### "]),
        Glyph([" ### ",   // 2
               "#   #",
               "    #",
               "   # ",
               "  #  ",
               " #   ",
               "#####"]),
        Glyph(["#####",   // 3
               "   # ",
               "  #  ",
               "   # ",
               "    #",
               "#   #",
               " ### "]),
        Glyph(["   # ",   // 4
               "  ## ",
               " # # ",
               "#  # ",
               "#####",
               "   # ",
               "   # "]),
        Glyph(["#####",   // 5
               "#    ",
               "#### ",
               "    #",
               "    #",
               "#   #",
               " ### "]),
        Glyph(["  ## ",   // 6
               " #   ",
               "#    ",
               "#### ",
               "#   #",
               "#   #",
               " ### "]),
        Glyph(["#####",   // 7
               "    #",
               "   # ",
               "  #  ",
               " #   ",
               " #   ",
               " #   "]),
        Glyph([" ### ",   // 8
               "#   #",
               "#   #",
               " ### ",
               "#   #",
               "#   #",
               " ### "]),
        Glyph([" ### ",   // 9
               "#   #",
               "#   #",
               " ####",
               "    #",
               "   # ",
               " ##  "]),
    ]

    /// A narrow colon — 1 column wide, so `MM:SS` doesn't develop a gap in the middle.
    public static let colon = Glyph(["",
                                     "#",
                                     "",
                                     "",
                                     "",
                                     "#",
                                     ""])

    /// A narrow blank, used to blink the colon without the digits shifting.
    public static let colonBlank = Glyph(["", "", "", "", "", "", ""])

    /// Maps a character to its glyph. Only `0`-`9` and `:` exist — this app never
    /// renders a letter in dot-matrix (letters are the system monospaced face instead,
    /// per the Teenage Engineering monospace rule in ISA § Principles).
    public static func glyph(for character: Character) -> Glyph? {
        if let value = character.wholeNumberValue, (0...9).contains(value) {
            return digits[value]
        }
        if character == ":" { return colon }
        return nil
    }

    /// Lays a string out into a single grid, returning the lit/unlit matrix and its width.
    /// `columnGap` is the number of empty columns inserted between glyphs.
    ///
    /// Returns `cells` indexed `[row][column]`.
    public static func layout(_ text: String, columnGap: Int = 1) -> (cells: [[Bool]], width: Int) {
        var glyphs: [Glyph] = []
        for character in text {
            if let glyph = glyph(for: character) { glyphs.append(glyph) }
        }
        guard !glyphs.isEmpty else { return ([], 0) }

        let totalWidth = glyphs.reduce(0) { $0 + $1.width } + columnGap * (glyphs.count - 1)
        var cells = Array(repeating: Array(repeating: false, count: totalWidth), count: height)

        var xOffset = 0
        for glyph in glyphs {
            for (x, y) in glyph.litDots {
                cells[y][xOffset + x] = true
            }
            xOffset += glyph.width + columnGap
        }
        return (cells, totalWidth)
    }

    /// Formats a duration for matrix display. Always `MM:SS`, zero-padded, and clamped
    /// at zero so a negative remaining time never renders a minus sign we have no glyph for.
    public static func clockString(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}
