//
//  ParserLink.swift
//  riidaa
//
//  Created by Pierre on 2025/04/18.
//

import SwiftUI

struct ParserLink: View {
    
    @State var link: LinkContent
    
    var body: some View {
        switch link.data {
        case .text(let text):
            ParserText(text: text.content)
        case .array(let arr):
            ParserList(array: arr, prefix: nil)
        case .container(let container):
            ParserContainer(element: container)
        default:
            Text("@lnk>\(link.data)")
        }
        if let linkedWord = link.linkedWord {
            ForEach(linkedWord.parseDefinition, id: \.self) { definition in
                VStack {
                    switch (definition) {
                    case .text(let s):
                        Text(s.content)
                    case .detailed(let d):
                        DetailedView(structuredContent: d)
                    case .deinflection(let d):
                        EmptyView()
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }
}

#Preview {
    ParserLink(link: LinkContent(href: "?query=%E3%81%9D%E3%81%86%E8%A8%80%E3%81%86&wildcards=off&primary_reading=%E3%81%9D%E3%81%86%E3%81%84%E3%81%86", data: .text(StringContent(content: "そーゆー"))))
}
