//
//  TermMeta.swift
//  riidaa
//

import Foundation

public struct PitchAccent: Hashable {
    public let position: Int
    public let devoice: [Int]

    public func category(moraCount: Int) -> String {
        if position == 0 { return "heiban" }
        if position == 1 { return "atamadaka" }
        if position >= moraCount { return "odaka" }
        return "nakadaka"
    }

    /// Small kana combine with the preceding mora
    public static func moraCount(of reading: String) -> Int {
        let combining: Set<Character> = [
            "ゃ", "ゅ", "ょ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "ゎ",
            "ャ", "ュ", "ョ", "ァ", "ィ", "ゥ", "ェ", "ォ", "ヮ",
        ]
        return reading.filter { !combining.contains($0) }.count
    }
}

public struct TermFrequency: Hashable {
    public let value: Int64?
    public let display: String
}

public struct TermMetaDB: Hashable {
    public enum Content: Hashable {
        case frequency(TermFrequency)
        case pitch([PitchAccent])
    }

    public let term: String
    public let reading: String
    let dictionary: DictionaryDB
    public let content: Content

    public func applies(toReading termReading: String) -> Bool {
        reading.isEmpty || reading == termReading
    }
}

public struct TermMetaParser {

    /// Decodes the `data` element of a `[term, mode, data]` triple, or nil
    /// doesn't handle and data that doesn't match the spec.
    public static func parse(mode: String, data: Any) -> (reading: String, content: TermMetaDB.Content)? {
        switch mode {
        case "freq":
            return parseFrequency(data)
        case "pitch":
            return parsePitch(data)
        default:
            return nil
        }
    }

    private static func parseFrequency(_ data: Any) -> (reading: String, content: TermMetaDB.Content)? {
        if let map = data as? [String: Any], let reading = map["reading"] as? String {
            guard let inner = map["frequency"], let frequency = frequencyValue(inner) else { return nil }
            return (reading, .frequency(frequency))
        }
        guard let frequency = frequencyValue(data) else { return nil }
        return ("", .frequency(frequency))
    }

    private static func frequencyValue(_ data: Any) -> TermFrequency? {
        if let number = data as? Int64 {
            return TermFrequency(value: number, display: String(number))
        }
        if let number = data as? Int {
            return TermFrequency(value: Int64(number), display: String(number))
        }
        if let number = data as? Double {
            return TermFrequency(value: Int64(number), display: String(Int64(number)))
        }
        if let text = data as? String {
            return TermFrequency(value: Int64(text), display: text)
        }
        if let map = data as? [String: Any] {
            let value = (map["value"] as? Int).map(Int64.init) ?? (map["value"] as? Int64)
            let display = map["displayValue"] as? String ?? value.map(String.init)
            guard let display = display else { return nil }
            return TermFrequency(value: value, display: display)
        }
        return nil
    }

    private static func parsePitch(_ data: Any) -> (reading: String, content: TermMetaDB.Content)? {
        guard let map = data as? [String: Any],
              let reading = map["reading"] as? String,
              let pitches = map["pitches"] as? [[String: Any]] else {
            return nil
        }
        let accents: [PitchAccent] = pitches.compactMap { pitch in
            guard let position = pitch["position"] as? Int else { return nil }
            return PitchAccent(position: position, devoice: pitch["devoice"] as? [Int] ?? [])
        }
        guard !accents.isEmpty else { return nil }
        return (reading, .pitch(accents))
    }

}

/// Collapses the metadata applying to one term into the strings the lookup panel and the Anki
/// export both read, so the two can't drift apart.
public struct TermMetaSummary {
    let pitches: [PitchAccent]
    let frequencies: [(dictionary: String, frequency: TermFrequency)]
    let reading: String

    init(meta: [TermMetaDB], reading: String) {
        self.reading = reading
        let applicable = meta.filter { $0.applies(toReading: reading) }
        self.pitches = applicable.flatMap { entry -> [PitchAccent] in
            if case .pitch(let accents) = entry.content { return accents }
            return []
        }
        self.frequencies = applicable.compactMap { entry in
            if case .frequency(let frequency) = entry.content {
                return (entry.dictionary.title, frequency)
            }
            return nil
        }
    }

    public var isEmpty: Bool { pitches.isEmpty && frequencies.isEmpty }

    public var pitchPositions: [String] {
        deduplicated(pitches.map { "[\($0.position)]" })
    }

    public var pitchCategories: [String] {
        let mora = PitchAccent.moraCount(of: reading)
        return deduplicated(pitches.map { $0.category(moraCount: mora) })
    }

    /// Deduplicated: metadata is looked up under both the term and its reading, and a rating
    /// filed under both comes back twice.
    public var frequencyLabels: [String] {
        deduplicated(frequencies.map { "\($0.dictionary): \($0.frequency.display)" })
    }

    /// Lower means more common.
    public var frequencySortValue: Int64? {
        frequencies.compactMap { $0.frequency.value }.min()
    }

    private func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
