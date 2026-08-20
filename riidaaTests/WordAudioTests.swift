//
//  WordAudioTests.swift
//  riidaaTests
//

import Foundation
import Testing
@testable import riidaa

struct WordAudioTests {

    private func query(_ url: URL) -> [String: String] {
        var items: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            items[item.name] = item.value
        }
        return items
    }

    @Test func buildsTheEndpointUrl() throws {
        let url = try #require(WordAudio.url(term: "夫妻", reading: "ふさい"))
        let items = query(url)
        #expect(items["kanji"] == "夫妻")
        #expect(items["kana"] == "ふさい")
        // Without a media extension AnkiMobile won't download it at all.
        #expect(items["fakePath"]?.hasSuffix(".mp3") == true)

        let kanaOnly = try #require(WordAudio.url(term: "", reading: "ねこ"))
        #expect(query(kanaOnly)["kanji"] == "ねこ")

        #expect(WordAudio.url(term: " ", reading: "") == nil)
    }

    /// A real recording redirects to a CDN copy; a miss serves a fixed "not found" clip from
    /// the requested URL, so a changed URL is the whole signal.
    @Test func recognisesARealRecordingByItsRedirect() throws {
        let requested = try #require(WordAudio.url(term: "猫", reading: "ねこ"))
        let cdn = try #require(URL(string: "https://cdn.innovativelanguage.com/a/93487.mp3"))

        #expect(WordAudio.isRecording(requested: requested, resolved: cdn))
        #expect(!WordAudio.isRecording(requested: requested, resolved: requested))
        #expect(!WordAudio.isRecording(requested: requested, resolved: nil))
    }

}
