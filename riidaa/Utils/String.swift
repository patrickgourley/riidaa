//
//  String.swift
//  riidaa
//
//  Created by Pierre on 2025/04/04.
//

import Foundation

extension String: @retroactive Identifiable {
    public var id: String {self}
}

extension String {
    
    public func katakanaToHiragana() -> String {
        var hiragana = ""
        for scalar in self.unicodeScalars {
            let value = scalar.value
            if (0x30A1...0x30F6).contains(value) {
                if let hiraganaScalar = UnicodeScalar(value - 0x60) {
                    hiragana.append(Character(hiraganaScalar))
                    continue
                }
            }
            hiragana.append(Character(scalar))
        }
        return hiragana
    }

    /// Replaces each long-vowel mark (ー / chōonpu) with the vowel kana of the preceding
    /// character, so casual spellings (そー, めんどくせー, …) can be matched against their
    /// standard dictionary forms (そう, …). Operates on hiragana; combine with
    /// `katakanaToHiragana()` first. Generalizes the previous hard-coded そー/こー/どー cases.
    public func expandLongVowels() -> String {
        let aRow: Set<Character> = ["あ","か","が","さ","ざ","た","だ","な","は","ば","ぱ","ま","や","ら","わ","ゃ","ぁ"]
        let iRow: Set<Character> = ["い","き","ぎ","し","じ","ち","ぢ","に","ひ","び","ぴ","み","り","ぃ"]
        let uRow: Set<Character> = ["う","く","ぐ","す","ず","つ","づ","ぬ","ふ","ぶ","ぷ","む","ゆ","る","ゅ","ぅ"]
        let eRow: Set<Character> = ["え","け","げ","せ","ぜ","て","で","ね","へ","べ","ぺ","め","れ","ぇ"]
        let oRow: Set<Character> = ["お","こ","ご","そ","ぞ","と","ど","の","ほ","ぼ","ぽ","も","よ","ろ","を","ょ","ぉ"]

        var result = ""
        var previous: Character? = nil
        for ch in self {
            guard ch == "ー", let p = previous else {
                result.append(ch)
                previous = ch
                continue
            }
            let vowel: Character?
            if aRow.contains(p) { vowel = "あ" }
            else if iRow.contains(p) { vowel = "い" }
            else if uRow.contains(p) { vowel = "う" }
            else if eRow.contains(p) { vowel = "え" }
            else if oRow.contains(p) { vowel = "う" }
            else { vowel = nil }

            if let vowel = vowel {
                result.append(vowel)
                previous = vowel
            } else {
                result.append(ch)
                previous = ch
            }
        }
        return result
    }

}
