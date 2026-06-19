//
//  JapaneseParser.swift
//  riidaa
//
//  Created by Pierre on 2025/03/27.
//

import CoreData

public struct TermDeinflection : Hashable {
    public static func == (lhs: TermDeinflection, rhs: TermDeinflection) -> Bool {
        return lhs.term == rhs.term && lhs.deinflections == rhs.deinflections
    }
    
    public let term: TermDB
    public let deinflections: [Deinflection]
    
}

public struct ParsingResult : Hashable {
    
    public var original: String
    public let results: [TermDeinflection]
    
}

public struct Parser {
    
    
    /// Longest candidate token considered at each position. Japanese words are well within
    /// this; capping bounds the per-line work (was unbounded → O(n²) DB queries on long lines).
    private static let maxTokenLength = 15

    private static func normalized(_ text: String) -> String {
        text.katakanaToHiragana().expandLongVowels()
    }

    public static func parse(text: String) -> [ParsingResult] {
        guard !text.isEmpty else { return [] }
        let chars = Array(text)
        let n = chars.count
        var l = 0
        var parts: [ParsingResult] = []

        while l < n {
            let upper = min(n, l + maxTokenLength)

            // Build every candidate substring starting at `l` and collect all lookup texts,
            // so the whole position needs a single batched DB query instead of one per length.
            var candidates: [(cut: String, deinflections: [Deinflection])] = []
            var lookupTexts = Set<String>()
            for end in stride(from: upper, to: l, by: -1) {
                let cut = String(chars[l..<end])
                let deinflections = Inflection.deinflect(text: cut)
                candidates.append((cut: cut, deinflections: deinflections))
                for di in deinflections {
                    lookupTexts.insert(di.text)
                    lookupTexts.insert(di.text.katakanaToHiragana())
                    lookupTexts.insert(Parser.normalized(di.text))
                }
            }

            let results = SQLiteManager.shared.findTerms(texts: Array(lookupTexts))

            var possibilities: [ParsingResult] = []
            for candidate in candidates {
                var terms: [TermDeinflection] = []
                for deinflection in candidate.deinflections {
                    let target = Parser.normalized(deinflection.text)
                    for term in results where
                        (Parser.normalized(term.term) == target ||
                         Parser.normalized(term.reading) == target) &&
                        (deinflection.types.isEmpty ||
                         term.wordTypes.isEmpty ||
                         deinflection.types.inflectionMatch(wl: term.wordTypes)) {
                        terms.append(TermDeinflection(term: term, deinflections: [deinflection]))
                    }
                }

                if !terms.isEmpty {
                    let groupedTerms = Dictionary(grouping: terms, by: { $0.term })
                    let mergedTerms: [TermDeinflection] = groupedTerms.map { (term, group) in
                        let combinedDeinflections = group.flatMap { $0.deinflections }
                        return TermDeinflection(term: term, deinflections: combinedDeinflections)
                    }

                    possibilities.append(ParsingResult(
                        original: candidate.cut,
                        results: mergedTerms.sorted{
                            if $0.term.reading == candidate.cut && $1.term.reading != candidate.cut {
                                return true
                            } else if $0.term.reading != candidate.cut && $1.term.reading == candidate.cut {
                                return false
                            } else {
                                return $0.term.score > $1.term.score
                            }
                        }
                    ))
                }
            }

            if !possibilities.isEmpty {
                guard let bestPos = possibilities.max(by: {a, b in
                    guard let af = a.results.first, let bf = b.results.first else {return false}
                    return a.original.count == b.original.count ? af.term.score < bf.term.score : a.original.count < b.original.count
                }) else { break }
                parts.append(bestPos)
                l += bestPos.original.count
            } else {
                let c = chars[l]
                if var lastPart = parts.last, lastPart.results.isEmpty {
                    lastPart.original += String(c)
                    parts[parts.count - 1] = lastPart
                } else {
                    parts.append(ParsingResult(original: String(c), results: []))
                }
                l += 1
            }
        }
        return parts
    }
    
}
