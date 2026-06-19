//
//  ParserList.swift
//  riidaa
//
//  Created by Pierre on 2025/04/18.
//

import SwiftUI

struct ParserList: View {
    
    @State var array: [[StructuredContent]]
    @State var prefix: String?
    
    var body: some View {
        if array.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading) {
                ForEach(Array(array.enumerated()), id: \.offset) { _, elems in
                    HStack(alignment: .top) {
                        if let prefix = prefix {
                            Text(prefix)
                        }
                        ListElement(array: elems)
                    }
                }
            }
        }
    }
}

struct ListElement: View {
    
    @State var array: [StructuredContent]
    
    var body: some View {
        switch array.first {
        case .inlineContainer(_), .text(_), .link(_):
            if array.count > 1 {
                HStack(alignment: .top, spacing: 5) {
                    ForEach(Array(array.enumerated()), id: \.offset) { _, elem in
                        switch elem {
                        case .text(let s):
                            ParserText(text: s.content)
                                .padding([.trailing], 5)
                        case .inlineContainer(let c):
                            ParserInlineContainer(element: c)
                        case .link(let l):
                            VStack(alignment: .leading) {
                                ParserLink(link: l)
                            }
                        default:
                            DetailedView(structuredContent: elem)
                        }
                    }
                }
            } else if let first = array.first {
                DetailedView(structuredContent: first)
            }
        default:
            if let elem = array.first {
                switch elem {
                case .list(let list):
                    ParserList(array: list.content, prefix: list.prefix)
                case .numberedList(let list):
                    ParserNumberedList(array: list.content)
                    
                case .container(let container):
                    ParserContainer(element: container)
                case .link(let lnk):
                    ParserLink(link: lnk)
                default:
                    DetailedView(structuredContent: elem)
                }
            } else {
                EmptyView()
            }
        }
    }
}

#Preview {
    ParserList(array: [[.text(StringContent(content: "->"))], [.text(StringContent(content: "test")),.text(StringContent(content: "test")),.text(StringContent(content: "test"))]], prefix: nil)
}
