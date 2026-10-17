import Foundation

/// Prepared with the catalog, never rebuilt for each keystroke.
struct ApplicationSearchProfile: Equatable, Sendable {
    enum Origin: String, Sendable { case name, pinyin, initials }

    struct Term: Equatable, Sendable {
        let name: String
        let origin: Origin
        let normalized: String
        let compact: String
        let units: [UInt32]
        let wordStarts: [Bool]
        let words: [[UInt32]]

        init(name: String, text: String, origin: Origin) {
            self.name = name
            self.origin = origin
            normalized = ApplicationSearchProfile.normalize(text)
            compact = ApplicationSearchProfile.compact(normalized)
            let folded = text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .init(identifier: "en_US_POSIX"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var units: [UInt32] = [], starts: [Bool] = [], words: [[UInt32]] = [], word: [UInt32] = []
            var previousIsLetter = false, previousIsLowercase = false
            for scalar in folded.unicodeScalars {
                let isLetter = CharacterSet.alphanumerics.contains(scalar)
                let boundary = isLetter && (!previousIsLetter || (previousIsLowercase && CharacterSet.uppercaseLetters.contains(scalar)))
                let lowered = Array(String(scalar).lowercased().unicodeScalars.map(\.value))
                if boundary || !isLetter {
                    if !word.isEmpty { words.append(word); word = [] }
                }
                if isLetter { word += lowered }
                if !CharacterSet.whitespacesAndNewlines.contains(scalar), scalar.value != 39, scalar.value != 0x2019 {
                    for (index, unit) in lowered.enumerated() {
                        units.append(unit)
                        starts.append(boundary && index == 0)
                    }
                }
                previousIsLetter = isLetter
                previousIsLowercase = CharacterSet.lowercaseLetters.contains(scalar)
            }
            if !word.isEmpty { words.append(word) }
            self.units = units
            wordStarts = starts
            self.words = origin == .name ? words.filter { $0.count >= 4 && $0.allSatisfy { (97...122).contains($0) } } : []
        }
    }

    let terms: [Term]
    /// Normalized display name, prepared once for deterministic final tie-breaking.
    let sortName: String

    init(names: [String]) {
        var seen = Set<String>(), terms: [Term] = []
        for name in names where !Self.normalize(name).isEmpty && seen.insert(Self.normalize(name)).inserted {
            terms.append(Term(name: name, text: name, origin: .name))
            if name.range(of: "\\p{Han}", options: .regularExpression) != nil,
               let latin = name.applyingTransform(.toLatin, reverse: false) {
                let syllables = latin.folding(options: .diacriticInsensitive, locale: nil).split(whereSeparator: \.isWhitespace)
                terms.append(Term(name: name, text: syllables.joined(), origin: .pinyin))
                terms.append(Term(name: name, text: syllables.compactMap(\.first).map(String.init).joined(), origin: .initials))
            }
        }
        self.terms = terms
        sortName = terms.first?.normalized ?? ""
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .init(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func compact(_ value: String) -> String {
        value.filter { !$0.isWhitespace && $0 != "'" && $0 != "’" }
    }
}
