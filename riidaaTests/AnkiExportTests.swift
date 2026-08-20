//
//  AnkiExportTests.swift
//  riidaaTests
//

import Foundation
import Testing
@testable import riidaa

struct AnkiExportTests {

    private func makeTerm(term: String, reading: String) -> TermDB {
        TermDB(
            term: term, reading: reading, definitionTags: [], wordTypes: [], score: 0,
            definitions: Data(), sequenceNumber: 0, termTags: [],
            dictionary: DictionaryDB(id: 1, revision: "", title: "Jitendex", format: 3),
            exportedToAnki: false
        )
    }

    private func makeExport(fields: [AnkiFieldToken: String]) -> AnkiExport {
        AnkiExport(profile: "ユーザー 1", deck: "Mining", noteType: "Lapis", fields: fields)
    }

    /// Fields AnkiMobile receives, keyed by name (`fldWord=…` → `Word`).
    private func exportedFields(_ url: URL) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return [:]
        }
        var fields: [String: String] = [:]
        for item in items where item.name.hasPrefix("fld") {
            fields[String(item.name.dropFirst(3))] = item.value ?? ""
        }
        return fields
    }

    @Test func exportsMappedFieldsAndSkipsTheRest() throws {
        let context = AnkiNoteContext(
            term: makeTerm(term: "番地", reading: "ばんち"),
            sentence: "この番地はどこですか",
            source: MangaSource(title: "よつばと！", volume: 3, page: 42),
            audioURL: WordAudio.url(term: "番地", reading: "ばんち")
        )
        let url = try #require(makeExport(fields: [
            .word: "Word", .reading: "Word Reading", .furigana: "Word Furigana",
            .sentence: "Sentence", .source: "Notes", .audio: "Word Audio", .glossary: "Glossary",
        ]).addNoteURL(context: context, callback: "riidaa://done"))
        let fields = exportedFields(url)

        #expect(fields["Word"] == "番地")
        #expect(fields["Word Reading"] == "ばんち")
        #expect(fields["Word Furigana"] == "番地[ばんち]")
        #expect(fields["Sentence"] == "この番地はどこですか")
        #expect(fields["Notes"] == "よつばと！ vol.3 p.42")
        #expect(fields["Word Audio"]?.hasPrefix("https://assets.languagepod101.com/") == true)
        // Mapped but with nothing to put in it.
        #expect(fields["Glossary"] == nil)

        #expect(makeExport(fields: [:]).addNoteURL(context: context, callback: "x") == nil)
    }

    /// `&`, `=` and `+` in a value used to split it into extra fields, and the callback carries
    /// its own query string that has to survive as one value.
    @Test func escapesQueryDelimiters() throws {
        let context = AnkiNoteContext(
            term: makeTerm(term: "猫", reading: "ねこ"), sentence: "A&B=C+D", source: nil
        )
        let url = try #require(makeExport(fields: [.word: "Word", .sentence: "Sentence"])
            .addNoteURL(context: context, callback: "riidaa://anki-callback?term=42"))

        #expect(exportedFields(url)["Sentence"] == "A&B=C+D")
        #expect(exportedFields(url).count == 2)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "x-success" }?.value == "riidaa://anki-callback?term=42")
    }

    /// The bolded word is the inflected form the parser matched, at its exact offset — and a
    /// match that doesn't land there must leave the sentence alone.
    @Test func boldsTheLookedUpWord() throws {
        func sentence(_ match: SentenceMatch?, in text: String) throws -> String? {
            let context = AnkiNoteContext(
                term: makeTerm(term: "思う", reading: "おもう"), sentence: text, source: nil, match: match
            )
            let url = try #require(makeExport(fields: [.sentence: "Sentence"])
                .addNoteURL(context: context, callback: "x"))
            return exportedFields(url)["Sentence"]
        }

        #expect(try sentence(SentenceMatch(surface: "思っている", offset: 8), in: "君は学校を何だと思っているのかね")
            == "君は学校を何だと<b>思っている</b>のかね")
        // The second occurrence, not the first.
        #expect(try sentence(SentenceMatch(surface: "猫", offset: 2), in: "猫と猫") == "猫と<b>猫</b>")

        for bad in [SentenceMatch(surface: "犬", offset: 0), SentenceMatch(surface: "猫", offset: 99)] {
            #expect(try sentence(bad, in: "猫がいる") == "猫がいる")
        }
    }

    /// Alias order is what puts the sentence in `Sentence` rather than Lapis's `SelectionText`,
    /// and no two tokens may claim the same field.
    @Test func mapsRealNoteTypesAutomatically() {
        let lapis = ["Expression", "ExpressionFurigana", "ExpressionReading", "ExpressionAudio",
                     "SelectionText", "MainDefinition", "DefinitionPicture", "Sentence",
                     "SentenceFurigana", "SentenceAudio", "Picture", "Glossary", "Hint",
                     "PitchPosition", "PitchCategories", "Frequency", "FreqSort", "MiscInfo"]
        let mapped = AnkiFieldToken.suggestedMapping(for: lapis)
        #expect(mapped[.word] == "Expression")
        #expect(mapped[.sentence] == "Sentence")
        #expect(mapped[.furigana] == "ExpressionFurigana")
        #expect(mapped[.audio] == "ExpressionAudio")
        #expect(mapped[.picture] == "Picture")
        #expect(mapped[.pitch] == "PitchPosition")
        #expect(mapped[.frequency] == "Frequency")
        #expect(mapped[.source] == "MiscInfo")
        #expect(Set(mapped.values).count == mapped.count)

        let kaishi = AnkiFieldToken.suggestedMapping(
            for: ["Word", "Word Reading", "Word Meaning", "Word Furigana", "Word Audio",
                  "Sentence", "Sentence Furigana", "Notes", "Pitch Accent", "Frequency", "Picture"]
        )
        #expect(kaishi[.word] == "Word")
        #expect(kaishi[.meaning] == "Word Meaning")
        #expect(kaishi[.pitch] == "Pitch Accent")
        #expect(kaishi[.source] == "Notes")
        #expect(kaishi[.sentenceFurigana] == "Sentence Furigana")

        #expect(AnkiFieldToken.suggestedMapping(for: ["Champ1", "Zzz"]).isEmpty)
    }

    /// Switching note type used to carry the previous one's field names across, producing
    /// "field MiscInfo does not exist" on export.
    @Test func dropsMappingsTheNoteTypeDoesNotHave() {
        let settings = SettingsModel()
        let lapis = AnkiInfo.NoteType(name: "Lapis", kind: "normal",
            fields: [.init(name: "Expression"), .init(name: "MiscInfo"), .init(name: "Sentence")])
        let kaishi = AnkiInfo.NoteType(name: "Kaishi", kind: "normal",
            fields: [.init(name: "Word"), .init(name: "Sentence"), .init(name: "Notes")])

        settings.ankiNoteType = lapis
        settings.autoMapAnkiFields(for: lapis)
        #expect(settings.ankiFields["source"] == "MiscInfo")

        settings.ankiNoteType = kaishi
        #expect(settings.ankiFields["source"] == nil)
        #expect(settings.ankiFields["sentence"] == "Sentence")

        settings.autoMapAnkiFields(for: kaishi)
        #expect(settings.ankiFields["word"] == "Word")
        #expect(settings.ankiFields["source"] == "Notes")
    }

}
