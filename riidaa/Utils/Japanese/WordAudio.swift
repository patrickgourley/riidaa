//
//  WordAudio.swift
//  riidaa
//

import Foundation

/// Pronunciation audio from JapanesePod101's dictionary endpoint
public struct WordAudio {

    private static let endpoint = "https://assets.languagepod101.com/dictionary/japanese/audiomp3.php"

    private static let cacheQueue = DispatchQueue(label: "dev.repierre.riidaa.wordaudio")
    private static var availabilityCache: [URL: Bool] = [:]

    public static func url(term: String, reading: String) -> URL? {
        let kanji = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let kana = reading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kanji.isEmpty || !kana.isEmpty else { return nil }

        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "kanji", value: kanji.isEmpty ? kana : kanji),
            URLQueryItem(name: "kana", value: kana.isEmpty ? kanji : kana),
            URLQueryItem(name: "fakePath", value: "audio.mp3"),
        ]
        return components?.url
    }

    /// The endpoint never 404s: a word it knows redirects to a CDN copy, one it doesn't serves a
    /// fixed "not found" clip from the requested URL
    static func isRecording(requested: URL, resolved: URL?) -> Bool {
        guard let resolved = resolved else { return false }
        return resolved != requested
    }

    /// Answers on the main queue, cached for the session.
    static func checkAvailability(of url: URL, completion: @escaping (Bool) -> Void) {
        if let cached = cacheQueue.sync(execute: { availabilityCache[url] }) {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let available = isRecording(requested: url, resolved: response?.url)
            cacheQueue.sync { availabilityCache[url] = available }
            DispatchQueue.main.async { completion(available) }
        }.resume()
    }

}
