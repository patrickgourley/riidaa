//
//  ParserContainer.swift
//  riidaa
//
//  Created by Pierre on 2025/04/18.
//

import SwiftUI

struct ParserContainer: View {
    
    @State var element: StructuredContentContainer
    
    var body: some View {
        if element.tag == "table" {
            ParserTable(container: element)
        } else {
            switch element.data {
            case .array(let array):
                ParserList(array: array, prefix: nil)
            case .text(let text):
                ParserText(text: text.content)
            case .container(let container):
                ParserContainer(element: container)
            case .list(let list):
                ParserList(array: list.content, prefix: list.prefix)
            case .link(let link):
                ParserLink(link: link)
            default:
                DetailedView(structuredContent: element.data)
            }
        }
    }
}

#Preview {
    ParserContainer(element: StructuredContentContainer(data: .newline, tag: ""))
}
