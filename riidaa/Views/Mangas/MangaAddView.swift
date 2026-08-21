//
//  MangaAddView.swift
//  riidaa
//
//  Created by Pierre on 2025/02/12.
//

import SwiftUI
import Anilist

struct MangaAddView: View {
    
    @State var mangaTitle = ""
    @State var searchMangasList: [MangaResultModel] = []
    @Environment(\.dismiss) var dismiss
    @State var isSearching = false
    @State var searchMessage: String? = nil
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.managedObjectContext) var moc
    
    @EnvironmentObject var settings: SettingsModel
    
    
    var body: some View {
        VStack {
            HStack {
                Text("Add a manga")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 4) {
                Text("Search AniList by title, then pick the right match. Its cover and details are used for your library — you add volume files afterwards.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.bottom, 10)

            HStack(spacing: 8) {
                TextField("Search AniList by title...", text: $mangaTitle, onCommit: searchMangas)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .overlay(
                    HStack {
                        Spacer()
                        Button(action: {
                            mangaTitle = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .scaleEffect(mangaTitle.isEmpty ? 0.5 : 1.2)
                                .opacity(mangaTitle.isEmpty ? 0 : 1)
                        }
                        .padding(.trailing, 8)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: mangaTitle)
                    }
                )
                .focused($isTextFieldFocused)
                .submitLabel(.search)
                .onSubmit(searchMangas)

                Button("Search", action: searchMangas)
                    .buttonStyle(.borderedProminent)
                    .disabled(mangaTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }
            .padding(.horizontal)
            
            ScrollView {
                if isSearching {
                    VStack {
                        ProgressView()
                            .controlSize(.regular)
                            .scaleEffect(2)
                        Text("Searching...")
                            .font(.headline)
                            .foregroundColor(.gray)
                            .padding(.top, 20)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else if let searchMessage = searchMessage {
                    VStack {
                        Image(systemName: "exclamationmark.circle")
                            .scaleEffect(2)
                            .foregroundColor(.gray)
                        Text(searchMessage)
                            .font(.headline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.top, 20)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else if searchMangasList.isEmpty && mangaTitle == "" {
                    VStack {
                        Image(systemName: "book.closed")
                        //                            .font(.largeTitle)
                            .scaleEffect(2)
                            .foregroundColor(.gray)
                        Text("Search AniList for a title")
                            .font(.headline)
                            .foregroundColor(.gray)
                            .padding(.top, 20)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    MangaAddResultView(searchMangasList: $searchMangasList, title: $mangaTitle)
                }
            }
            
        }
        .padding(.top, 20)
        .onAppear {
            isTextFieldFocused = true
        }
        .background(Color(.systemBackground))
    }
    
    private func applyResults(_ results: [MangaResultModel], matchesFound: Int) {
        self.searchMangasList = results
        if !results.isEmpty {
            self.searchMessage = nil
        } else if matchesFound > 0 {
            self.searchMessage = "Every match is already in your library."
        } else {
            self.searchMessage = "No manga found for “\(mangaTitle)”."
        }
    }

    private func searchFailed(_ error: Error) {
        self.searchMangasList = []
        self.searchMessage = "Search failed: \(error.localizedDescription)"
    }

    func searchMangas() {
        guard !mangaTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        self.searchMessage = nil
        self.isSearching = true

        if settings.adult {
            Network.shared.apollo.fetch(query: MangaSearchQueryAdultQuery(page: 1, search: .some(mangaTitle))) { result in
                switch result {
                case .success(let data):
                    let medias = data.data?.page?.media ?? []
                    let mangaIDs = MangaModel.fetchMangaAnilistIDs(moc: moc)
                    let results: [MangaResultModel] = medias.compactMap({ media in
                        guard let id = media?.id, !mangaIDs.contains(Int64(id)) else {
                            return nil
                        }
                        return MangaResultModel(
                            id: Int64(id),
                            title: media?.title?.native ?? media?.title?.romaji ?? media?.title?.english ?? "",
                            coverImage: media?.coverImage?.large ?? ""
                        )
                    })
                    self.applyResults(results, matchesFound: medias.count)
                case .failure(let err):
                    self.searchFailed(err)
                }
                self.isSearching = false
            }
        } else {
            Network.shared.apollo.fetch(query: MangaSearchQuery(page: 1, search: .some(mangaTitle))) { result in
                switch result {
                case .success(let data):
                    let medias = data.data?.page?.media ?? []
                    let mangaIDs = MangaModel.fetchMangaAnilistIDs(moc: moc)
                    let results: [MangaResultModel] = medias.compactMap({ media in
                        guard let id = media?.id, !mangaIDs.contains(Int64(id)) else {
                            return nil
                        }
                        return MangaResultModel(
                            id: Int64(id),
                            title: media?.title?.native ?? media?.title?.romaji ?? media?.title?.english ?? "",
                            coverImage: media?.coverImage?.large ?? ""
                        )
                    })
                    self.applyResults(results, matchesFound: medias.count)
                case .failure(let err):
                    self.searchFailed(err)
                }
                self.isSearching = false
            }
        }
    }
    
}

#Preview {
    MangaAddView()
        .environment(\.managedObjectContext, CoreDataManager.shared.container.viewContext)
}

