import Foundation

/// Pure, local application matching. A complete ranking selects one winner before diagnostics are capped.
enum ApplicationMatcher {
    static let maximumTextBytes = 12_000
    enum Kind: String, Equatable, Sendable {
        case exact, prefix, wordPrefix, substring, abbreviation, typo

        var priority: Int {
            switch self {
            case .exact: 6
            case .prefix: 5
            case .wordPrefix: 4
            case .substring: 3
            case .abbreviation: 2
            case .typo: 1
            }
        }
    }

    struct Candidate: Equatable, Sendable {
        let id: String
        let profile: ApplicationSearchProfile
    }

    struct Usage: Equatable, Sendable {
        var openCount: Int
        var lastOpenedAt: Date
    }

    struct Match: Equatable, Sendable {
        let id: String
        let kind: Kind
        let quality: Int
        let sortName: String
        let name: String
        let origin: ApplicationSearchProfile.Origin

        func outranks(_ other: Match) -> Bool {
            kind.priority != other.kind.priority ? kind.priority > other.kind.priority : quality > other.quality
        }

        func sameQuality(as other: Match) -> Bool { kind == other.kind && quality == other.quality }
    }

    enum Resolution: Equatable, Sendable {
        case notApplicable, noMatch, tooShort, selected(Match)
    }

    struct Evaluation: Equatable, Sendable {
        let resolution: Resolution
        let matches: [Match]
        let isPureLaunch: Bool

        var winner: Match? {
            if case .selected(let match) = resolution { return match }
            return nil
        }

        func clearsDraft(for applicationID: String) -> Bool {
            isPureLaunch && winner?.id == applicationID
        }
    }

    private struct Query {
        let normalized: String
        let units: [UInt32]
        let allowsBroadMatching: Bool
        let prefixIsLongEnough: Bool

        init(_ text: String) {
            normalized = ApplicationSearchProfile.normalize(text)
            units = Array(ApplicationSearchProfile.compact(normalized).unicodeScalars.map(\.value))
            allowsBroadMatching = (2...32).contains(normalized.count)
                && normalized.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
            let letters = normalized.filter { $0.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) }
            let isHan = !letters.isEmpty && letters.range(of: #"^\p{Han}[\p{Han}\p{M}]*$"#, options: .regularExpression) != nil
            prefixIsLongEnough = letters.count >= (isHan ? 2 : 3)
        }
    }

    static func evaluate(_ text: String, candidates: [Candidate], usage: [String: Usage] = [:]) -> Evaluation {
        let draft = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return .init(resolution: .notApplicable, matches: [], isPureLaunch: false) }
        let singleLine = draft.rangeOfCharacter(from: .newlines) == nil
        if singleLine {
            let result = evaluate(Query(draft), candidates: candidates, usage: usage, pure: true)
            if result.resolution != .noMatch { return result }
        }
        if let target = launchCommandTarget(in: draft) {
            return evaluate(Query(target), candidates: candidates, usage: usage, pure: singleLine)
        }
        return .init(resolution: singleLine ? .noMatch : .notApplicable, matches: [], isPureLaunch: false)
    }

    private static func evaluate(_ query: Query, candidates: [Candidate], usage: [String: Usage], pure: Bool) -> Evaluation {
        guard !query.units.isEmpty else { return .init(resolution: .noMatch, matches: [], isPureLaunch: false) }
        var byID: [String: Match] = [:]
        var tooShort = false
        for candidate in candidates {
            guard let match = bestMatch(query, candidate: candidate) else { continue }
            if match.kind == .prefix, !query.prefixIsLongEnough, (usage[candidate.id]?.openCount ?? 0) == 0 {
                tooShort = true
                continue
            }
            if let previous = byID[candidate.id], !match.outranks(previous),
               !match.sameQuality(as: previous) || match.sortName >= previous.sortName { continue }
            byID[candidate.id] = match
        }
        if byID.isEmpty, !tooShort, (4...32).contains(query.units.count),
           query.normalized.unicodeScalars.allSatisfy({ (97...122).contains($0.value) }) {
            for candidate in candidates {
                guard let match = typoMatch(query.units, candidate: candidate) else { continue }
                if let previous = byID[candidate.id], !match.outranks(previous),
                   !match.sameQuality(as: previous) || match.sortName >= previous.sortName { continue }
                byID[candidate.id] = match
            }
        }
        let precedes: (Match, Match) -> Bool = { lhs, rhs in
            if !lhs.sameQuality(as: rhs) { return lhs.outranks(rhs) }
            let left = usage[lhs.id], right = usage[rhs.id]
            let leftCount = left?.openCount ?? 0, rightCount = right?.openCount ?? 0
            if leftCount != rightCount { return leftCount > rightCount }
            if leftCount > 0, let left, let right, left.lastOpenedAt != right.lastOpenedAt {
                return left.lastOpenedAt > right.lastOpenedAt
            }
            if lhs.sortName != rhs.sortName { return lhs.sortName < rhs.sortName }
            return lhs.id < rhs.id
        }
        // Compare every identity, retaining only the ordered diagnostic window.
        // This produces the same first 32 as a full sort without sorting discarded matches.
        var matches: [Match] = []
        matches.reserveCapacity(32)
        for match in byID.values {
            if matches.count == 32, !precedes(match, matches[31]) { continue }
            var lower = 0, upper = matches.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if precedes(match, matches[middle]) { upper = middle }
                else { lower = middle + 1 }
            }
            matches.insert(match, at: lower)
            if matches.count > 32 { matches.removeLast() }
        }
        guard let first = matches.first else {
            return .init(resolution: tooShort ? .tooShort : .noMatch, matches: [], isPureLaunch: pure)
        }
        return .init(resolution: .selected(first), matches: matches, isPureLaunch: pure)
    }

    private static func bestMatch(_ query: Query, candidate: Candidate) -> Match? {
        var best: Match?
        for term in candidate.profile.terms {
            let kind: Kind
            let quality: Int
            if term.normalized == query.normalized {
                kind = .exact
                quality = 0
            } else if term.units.starts(with: query.units) {
                kind = .prefix
                quality = contiguousScore(start: 0, count: query.units.count, term: term)
            } else if query.allowsBroadMatching, let hit = contiguousMatch(query.units, term: term) {
                kind = hit.kind
                quality = hit.score
            } else if query.allowsBroadMatching, let score = abbreviationScore(query.units, term: term),
                      Double(score) >= 1.5 * Double(query.units.count - 2) + 4 {
                kind = .abbreviation
                quality = score
            } else { continue }
            let match = Match(id: candidate.id, kind: kind, quality: quality, sortName: candidate.profile.sortName,
                              name: term.name, origin: term.origin)
            if best == nil || match.outranks(best!) { best = match }
        }
        return best
    }

    private static func contiguousScore(start: Int, count: Int, term: ApplicationSearchProfile.Term) -> Int {
        (start..<(start + count)).reduce(0) { score, index in
            score + (index == 0 ? 4 : term.wordStarts[index] ? 3 : 2)
        }
    }

    private static func contiguousMatch(_ query: [UInt32], term: ApplicationSearchProfile.Term) -> (kind: Kind, score: Int)? {
        guard query.count <= term.units.count else { return nil }
        var best: (kind: Kind, score: Int)?
        for index in 0...(term.units.count - query.count) where term.units[index] == query[0] {
            guard term.units[index..<(index + query.count)].elementsEqual(query) else { continue }
            let kind: Kind = term.wordStarts[index] ? .wordPrefix : .substring
            let score = contiguousScore(start: index, count: query.count, term: term)
            if best == nil || kind.priority > best!.kind.priority || (kind == best!.kind && score > best!.score) {
                best = (kind, score)
            }
        }
        return best
    }

    private static func abbreviationScore(_ query: [UInt32], term: ApplicationSearchProfile.Term) -> Int? {
        // A linear precheck avoids allocating DP rows for names that cannot possibly align.
        var matched = 0
        for unit in term.units where unit == query[matched] {
            matched += 1
            if matched == query.count { break }
        }
        guard matched == query.count else { return nil }
        let unreachable = Int.min / 4
        var previous = [Int](repeating: unreachable, count: term.units.count)
        var current = previous
        for (row, unit) in query.enumerated() {
            var gap = unreachable
            for column in term.units.indices {
                if column >= 2 { gap = max(gap, previous[column - 2]) }
                guard term.units[column] == unit else { current[column] = unreachable; continue }
                let points = row == 0 && column == 0 ? 4 : term.wordStarts[column] ? 3 : 2
                if row == 0 { current[column] = points }
                else {
                    let adjacent = column > 0 ? previous[column - 1] : unreachable
                    current[column] = max(adjacent + points, gap + points - 1)
                }
            }
            swap(&previous, &current)
        }
        return previous.max()
    }

    private static func typoMatch(_ query: [UInt32], candidate: Candidate) -> Match? {
        var best: Match?
        for term in candidate.profile.terms where term.origin == .name {
            for word in term.words where word.first == query.first {
                for length in (query.count - 1)...(query.count + 1) where length >= 4 && length <= word.count {
                    guard hasSingleEdit(query, word[0..<length]) else { continue }
                    let match = Match(id: candidate.id, kind: .typo, quality: length == word.count ? 1 : 0,
                                      sortName: candidate.profile.sortName, name: term.name, origin: .name)
                    if best == nil || match.outranks(best!) { best = match }
                }
            }
        }
        return best
    }

    /// At distance one, substitution, insertion, deletion and one adjacent swap can be checked linearly.
    private static func hasSingleEdit(_ query: [UInt32], _ target: ArraySlice<UInt32>) -> Bool {
        var index = 0
        while index < min(query.count, target.count), query[index] == target[index] { index += 1 }
        if index == min(query.count, target.count) { return abs(query.count - target.count) == 1 }
        if query.count == target.count {
            if query[(index + 1)...].elementsEqual(target[(index + 1)...]) { return true }
            return index + 1 < query.count && query[index] == target[index + 1] && query[index + 1] == target[index]
                && query[(index + 2)...].elementsEqual(target[(index + 2)...])
        }
        if query.count == target.count + 1 { return query[(index + 1)...].elementsEqual(target[index...]) }
        return target.count == query.count + 1 && query[index...].elementsEqual(target[(index + 1)...])
    }

    /// Only the first line can introduce a launch command; following content stays in the draft.
    static func launchCommandTarget(in text: String) -> String? {
        var command = ApplicationSearchProfile.normalize(text.components(separatedBy: .newlines).first ?? "")
        for polite in ["请帮我", "帮我", "请", "please "] where command.hasPrefix(polite) {
            command = String(command.dropFirst(polite.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        guard let prefix = ["打开", "启动", "切换到", "切到", "open ", "launch ", "switch to "].first(where: command.hasPrefix) else { return nil }
        let target = command.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return target.isEmpty ? nil : target
    }
}
