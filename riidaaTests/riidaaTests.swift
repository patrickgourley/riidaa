//
//  riidaaTests.swift
//  riidaaTests
//
//  Created by Pierre on 2025/02/12.
//

import Testing
import riidaa

struct riidaaTests {
    
    func printDeinflectinos(deinflections: [Deinflection]) {
        for deinflection in deinflections {
            if deinflection.text == "" {
                continue
            }
            var text = "\t・\(deinflection.text)"
            if !deinflection.types.isEmpty {
                text += " ("
                for type in deinflection.types {
                    text += "\(type.rawValue), "
                }
                text.removeLast(2)
                text += ")"
            }
            text += " "
            for inflection in deinflection.inflections.reversed() {
                text += "\(inflection.description.short) -> "
            }
            if !deinflection.inflections.isEmpty {
                text.removeLast(4)
            }
            print(text)
        }
    }
    
    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        var res = Inflection.deinflect(text: "手伝わされる")
        print("Result 手伝わされる:")
        printDeinflectinos(deinflections: res)
        
        res = Inflection.deinflect(text: "してた")
        print("Result してた:")
        printDeinflectinos(deinflections: res)
        
        res = Inflection.deinflect(text: "言われたら")
        print("Result 言われたら:")
        printDeinflectinos(deinflections: res)
    }

}
