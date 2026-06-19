//
//  ParserLink.swift
//  riidaa
//
//  Created by Pierre on 2025/04/18.
//

import SwiftUI

struct ParserLink: View {

    let link: LinkContent

    @State private var linked: TermDB?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if linked != nil {
                    withAnimation { expanded.toggle() }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    DetailedView(structuredContent: link.data)
                    if linked != nil {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(linked == nil)

            if expanded, let linked {
                TermDefinitionsView(term: linked)
                    .padding(.leading, 12)
            }
        }
        .task(id: link.href) {
            guard let query = link.query else { return }
            linked = await Task.detached(priority: .userInitiated) {
                SQLiteManager.shared.findTerms(texts: [query]).first
            }.value
        }
    }
}

#Preview {
    ParserLink(link: LinkContent(href: "?query=%E3%81%9D%E3%81%86%E8%A8%80%E3%81%86&wildcards=off&primary_reading=%E3%81%9D%E3%81%86%E3%81%84%E3%81%86", data: .text(StringContent(content: "そーゆー"))))
}
