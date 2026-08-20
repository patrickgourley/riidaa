//
//  AnkiExport.swift
//  riidaa
//

import Foundation

/// One value a lookup can contribute to an Anki note. Raw values are persisted in
/// `SettingsModel.ankiFields`, so renaming a case drops that mapping for existing users.
enum AnkiFieldToken: String, CaseIterable, Identifiable {
    case word
    case reading
    case furigana
    case audio
    case picture
    case pitch
    case pitchCategories
    case frequency
    case frequencySort
    case meaning
    case glossary
    case sentence
    case source

    var id: String { rawValue }

    var label: String {
        switch self {
        case .word: return "word"
        case .reading: return "reading"
        case .furigana: return "furigana"
        case .audio: return "word audio"
        case .picture: return "page image"
        case .pitch: return "pitch accent"
        case .pitchCategories: return "pitch pattern"
        case .frequency: return "frequency"
        case .frequencySort: return "frequency (sort value)"
        case .meaning: return "meaning"
        case .glossary: return "full glossary"
        case .sentence: return "sentence"
        case .source: return "source"
        }
    }
}

extension AnkiFieldToken {

    /// Field names
    var fieldNameAliases: [String] {
        switch self {
        case .word:
            return ["word", "expression", "term", "vocab", "vocabulary", "kanji", "front"]
        case .reading:
            return ["reading", "wordreading", "expressionreading", "kana", "yomi"]
        case .furigana:
            return ["furigana", "wordfurigana", "expressionfurigana", "kanafurigana", "reading furigana"]
        case .audio:
            return ["wordaudio", "expressionaudio", "audio", "termaudio", "pronunciation"]
        case .picture:
            return ["picture", "image", "screenshot", "definitionpicture"]
        case .pitch:
            return ["pitch", "pitchaccent", "pitchposition", "accent"]
        case .pitchCategories:
            return ["pitchcategories", "pitchpattern", "pitchaccentcategories", "pitchaccentnotes"]
        case .frequency:
            return ["frequency", "freq", "frequencies"]
        case .frequencySort:
            return ["freqsort", "frequencysort", "sortfrequency"]
        case .meaning:
            return ["meaning", "maindefinition", "definition", "wordmeaning", "back"]
        case .glossary:
            return ["glossary", "glossaries", "definitions", "fullglossary"]
        case .sentence:
            return ["sentence", "examplesentence", "example", "context"]
        case .source:
            return ["source", "miscinfo", "notes", "book", "title"]
        }
    }

    /// Exact matches only, so an unfamiliar note type maps nothing rather than misfiling.
    static func suggestedMapping(for fields: [String]) -> [AnkiFieldToken: String] {
        func normalized(_ name: String) -> String {
            name.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let candidates = fields.map { (name: $0, key: normalized($0)) }

        var mapping: [AnkiFieldToken: String] = [:]
        var claimed = Set<String>()
        for token in AnkiFieldToken.allCases {
            for alias in token.fieldNameAliases.map(normalized) {
                guard let match = candidates.first(where: { !claimed.contains($0.name) && $0.key == alias })
                else {
                    continue
                }
                mapping[token] = match.name
                claimed.insert(match.name)
                break
            }
        }
        return mapping
    }
}

struct MangaSource: Equatable {
    let title: String
    let volume: Int64
    let page: Int64

    var formatted: String {
        "\(title) vol.\(volume) p.\(page)"
    }
}

/// The word as it appears in the sentence
struct SentenceMatch {
    let surface: String
    let offset: Int
}

/// The lookup being exported.
struct AnkiNoteContext {
    let term: TermDB
    let sentence: String
    let source: MangaSource?
    var match: SentenceMatch? = nil
    var meta: [TermMetaDB] = []
    var audioURL: URL? = nil
    var pictureURL: URL? = nil

    private var summary: TermMetaSummary {
        TermMetaSummary(meta: meta, reading: term.reading)
    }

    /// Falls back to the plain sentence if the match doesn't land where it claims, so a stale
    /// offset can't corrupt the text.
    private var emphasizedSentence: String {
        guard let match = match, !match.surface.isEmpty else { return sentence }
        let characters = Array(sentence)
        let end = match.offset + match.surface.count
        guard match.offset >= 0, end <= characters.count,
              String(characters[match.offset..<end]) == match.surface else {
            return sentence
        }
        return String(characters[0..<match.offset])
            + "<b>" + match.surface + "</b>"
            + String(characters[end...])
    }

    func value(for token: AnkiFieldToken) -> String? {
        let value: String?
        switch token {
        case .word:
            value = term.term
        case .reading:
            value = term.reading
        case .furigana:
            value = Furigana.annotate(term: term.term, reading: term.reading)
        case .audio:
            value = audioURL?.absoluteString
        case .picture:
            value = pictureURL?.absoluteString
        case .pitch:
            value = summary.pitchPositions.joined(separator: " ")
        case .pitchCategories:
            value = summary.pitchCategories.joined(separator: ",")
        case .frequency:
            value = summary.frequencyLabels.joined(separator: "<br>")
        case .frequencySort:
            value = summary.frequencySortValue.map(String.init)
        case .meaning:
            value = term.parseDefinition.first?.description
        case .glossary:
            // Deinflection entries are navigation hints, not meanings.
            value = term.parseDefinition
                .filter { definition in
                    if case .deinflection = definition { return false }
                    return true
                }
                .map(\.description)
                .joined(separator: "<br>")
        case .sentence:
            value = emphasizedSentence
        case .source:
            value = source?.formatted
        }
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }
}

/// Builds the `anki://x-callback-url/addnote` URL. Media can't be embedded: AnkiMobile
/// downloads a field whose value is a URL to an image or audio file, so it travels by reference.
struct AnkiExport {
    let profile: String
    let deck: String
    let noteType: String
    let fields: [AnkiFieldToken: String]

    private static let queryValueAllowed = CharacterSet.urlQueryAllowed
        .subtracting(CharacterSet(charactersIn: "&=+?#"))

    /// Nil when the note would carry no fields.
    func addNoteURL(context: AnkiNoteContext, callback: String) -> URL? {
        guard
            let profileEncoded = AnkiExport.encoded(profile),
            let deckEncoded = AnkiExport.encoded(deck),
            let noteTypeEncoded = AnkiExport.encoded(noteType),
            let callbackEncoded = AnkiExport.encoded(callback)
        else {
            return nil
        }

        var query = ""
        for token in AnkiFieldToken.allCases {
            guard
                let field = fields[token],
                let fieldEncoded = AnkiExport.encoded(field),
                let value = context.value(for: token),
                let valueEncoded = AnkiExport.encoded(value)
            else {
                continue
            }
            query += "&fld\(fieldEncoded)=\(valueEncoded)"
        }
        if query.isEmpty {
            return nil
        }

        return URL(string: "anki://x-callback-url/addnote?profile=\(profileEncoded)&deck=\(deckEncoded)&type=\(noteTypeEncoded)&x-success=\(callbackEncoded)\(query)")
    }

    private static func encoded(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
    }
}
