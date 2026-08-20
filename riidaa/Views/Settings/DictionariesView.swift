//
//  DictionariesView.swift
//  riidaa
//
//  Created by Pierre on 2025/02/21.
//

import SwiftUI
import CoreData

struct DictionariesView: View {
    
    @EnvironmentObject var appManager: AppManager
    @State private var isPickingDictionary = false
    
    var body: some View {
        ScrollView {
            if let preparing = appManager.preparing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(preparing.message)
                        .font(.subheadline)
                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 8)
            }

            if let purging = appManager.purging {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Clearing deleted dictionary")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(purging.fraction * 100))%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: purging.fraction)
                    Text("\((purging.total - purging.cleared).formatted()) entries left. Lookups keep working while this finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 8)
            }

            ForEach(appManager.dictionaries) { dictionary in
                DictionaryView(dictionary: dictionary, onUpdate: updateDictionary)
            }
        }
        .navigationTitle("Dictionaries")
        .toolbar {
            Button(action: {
                self.isPickingDictionary = true
            }) {
                Image(systemName: "plus")
            }
        }
        .fileImporter(isPresented: $isPickingDictionary, allowedContentTypes: [.zip]) { result in
            switch result {
            case .success(let file):
                processZipFile(path: file)
            case .failure(let error):
                print("error while picking dictionary file: \(error)")
            }
        }
        .alert(
            "Dictionary error",
            isPresented: Binding(
                get: { appManager.lastError != nil },
                set: { shown in if !shown { appManager.lastError = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(appManager.lastError ?? "") }
        )
    }

    /// Downloads `downloadUrl` and re-imports it, replacing the existing copy.
    func updateDictionary(_ dictionary: DictionaryDB) {
        guard let downloadUrl = dictionary.downloadUrl, let url = URL(string: downloadUrl) else {
            appManager.report(error: "This dictionary does not publish a download link.")
            return
        }

        let replacing = dictionary.id
        appManager.setProgress(DictionaryProgress(message: "Downloading…", value: 0, total: 0), for: replacing)

        Task {
            do {
                let (temporary, _) = try await URLSession.shared.download(from: url)
                // The importer keys off the extension, and a download has none.
                let archive = temporary.deletingPathExtension().appendingPathExtension("zip")
                try? FileManager.default.removeItem(at: archive)
                try FileManager.default.moveItem(at: temporary, to: archive)

                await MainActor.run {
                    self.processZipFile(path: archive, securityScoped: false, replacing: replacing)
                }
            } catch {
                appManager.setProgress(nil, for: replacing)
                appManager.report(error: "Download failed: \(error.localizedDescription)")
            }
        }
    }

    func processZipFile(path: URL, securityScoped: Bool = true, replacing: Int64? = nil) {
        // Snapshot taken here
        let installedSnapshot = appManager.dictionaries
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("dictionaries")
            let dicDirectory = documents.appendingPathComponent(UUID().uuidString)

            // Progress goes to AppManager, which outlives this screen.
            var done = 0
            var total = 0
            var reportingId: Int64? = replacing
            func report(_ message: String) {
                appManager.setProgress(
                    DictionaryProgress(message: message, value: done, total: total),
                    for: reportingId
                )
            }

            // Nothing reads these again once they are in SQLite; jitendex unpacks to 500 MB.
            defer {
                try? fileManager.removeItem(at: dicDirectory)
                if !securityScoped {
                    // riidaa downloaded this one, so it owns the file too.
                    try? fileManager.removeItem(at: path)
                }
            }

            do {
                let scoped = securityScoped && path.startAccessingSecurityScopedResource()
                if securityScoped && !scoped {
                    throw NSError(domain: "DictionaryImport", code: 0, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
                }
                defer {
                    if scoped {
                        path.stopAccessingSecurityScopedResource()
                    }
                }
                
                report("Unpacking…")
                try fileManager.createDirectory(at: dicDirectory, withIntermediateDirectories: true)
                try fileManager.unzipItem(at: path, to: dicDirectory)
                
                let dicContent = try fileManager.contentsOfDirectory(at: dicDirectory, includingPropertiesForKeys: nil)
                total = dicContent.count
                report("Processing dictionary…")
                
                guard let fileContent = try? Data(contentsOf: dicDirectory.appendingPathComponent("index.json")) else {
                    throw NSError(domain: "DictionaryImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find dictionary index.json"])
                }
                let dicJson = try JSONSerialization.jsonObject(with: fileContent)
                guard let dicJson = dicJson as? [String: Any] else {
                    throw NSError(domain: "DictionaryImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid file format"])
                }
                guard let revision = dicJson["revision"] as? String,
                      let title = dicJson["title"] as? String
                else {
                    throw NSError(domain: "DictionaryImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing mandatory properties"])
                }
                let sequenced = dicJson["sequenced"] as? Bool
                let format = dicJson["format"] as? Int
                let author = dicJson["author"] as? String
                let isUpdatable = dicJson["isUpdatable"] as? Bool
                let indexUrl = dicJson["indexUrl"] as? String
                let downloadUrl = dicJson["downloadUrl"] as? String
                let url = dicJson["url"] as? String
                let description = dicJson["description"] as? String
                let attribution = dicJson["attribution"] as? String
                let sourceLanguage = dicJson["sourceLanguage"] as? String
                let targetLanguage = dicJson["targetLanguage"] as? String
                let frequencyMode = dicJson["frequencyMode"] as? String

                let alreadyInstalled = installedSnapshot.first { existing in
                    if existing.id == replacing { return false }
                    if let indexUrl = indexUrl, let other = existing.indexUrl, !indexUrl.isEmpty {
                        return other == indexUrl
                    }
                    return existing.title == title
                }
                if let existing = alreadyInstalled {
                    let action = replacing == nil
                        ? "Use Update on it instead, or delete it first."
                        : "Delete one of them first."
                    throw NSError(domain: "DictionaryImport", code: 4, userInfo: [
                        NSLocalizedDescriptionKey: existing.revision == revision
                            ? "\(existing.title) is already installed."
                            : "\(existing.title) is already installed (revision \(existing.revision)). \(action)"
                    ])
                }

                
                var installed: DictionaryDB? = nil
                // Any throw past this point must take the row with it, or a half-imported
                // dictionary stays installed and feeds partial results into every lookup.
                defer {
                    if let installed = installed {
                        try? SQLiteManager.shared.deleteDictionary(dictionaryId: installed.id)
                        DispatchQueue.main.async {
                            appManager.dictionaries.removeAll { $0.id == installed.id }
                        }
                        appManager.purgeOrphanedEntries()
                    }
                }

                let dictionaryOrNil = SQLiteManager.shared.insertDictionary(revision: revision, title: title, sequenced: sequenced ?? false, format: format ?? 3, author: author, isUpdatable: isUpdatable ?? false, indexUrl: indexUrl, downloadUrl: downloadUrl, url: url, description: description, attribution: attribution, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, frequencyMode: frequencyMode)
                guard let dictionary = dictionaryOrNil else {
                    throw NSError(domain: "DictionaryImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Error saving dictionary"])
                }
                installed = dictionary
                // An update keeps reporting against the row the user can see
                if replacing == nil {
                    reportingId = dictionary.id
                    DispatchQueue.main.async { appManager.dictionaries.append(dictionary) }
                }
                report("Importing…")
                
                
                done += 1
                report("Processing dictionary…")
                
                
                var importedTerms = 0
                var importedMeta = 0

                var i = 1
                while true {
                    
                    let filename = "term_bank_\(i).json"
                    let filepath = dicDirectory.appending(component: filename)
                    
                    guard let fileContent = try? Data(contentsOf: filepath) else {
                        break
                    }
                    try autoreleasepool {
                        let termsJson = try? JSONSerialization.jsonObject(with: fileContent)
                        guard let termsJson = termsJson as? [[Any]] else {
                            throw NSError(domain: "DictionaryImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Error decoding terms"])
                        }
                        let insertTerms: [TermInsertion] = termsJson.compactMap({ t in
                            guard let term = t[0] as? String,
                                  let reading = t[1] as? String,
                                  let wordTypesJson = t[3] as? String,
                                  let score = t[4] as? Int64,
                                  let definitions = t[5] as? [Any],
                                  let sequence  = t[6] as? Int64,
                                  let termTagsJson = t[7]  as? String
                            else {
                                return nil
                            }
                            guard let definitionsEncoded = try? JSONSerialization.data(withJSONObject: definitions, options: []) else {
                                return nil
                            }
                            let definitionTags = t[2] as? String ?? ""
                            return TermInsertion(term: term, reading: reading, definitionTags: definitionTags, wordTypes: wordTypesJson, score: score, definitions: definitionsEncoded, sequence: sequence, termTags: termTagsJson, dictionaryId: dictionary.id)
                        })
                        guard SQLiteManager.shared.insertTerms(termsInsert: insertTerms) != nil else {
                            throw NSError(domain: "DictionaryImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Error saving terms"])
                        }
                        importedTerms += insertTerms.count
                        
                        i += 1
                        
                        done += 1
                        report("Processing dictionary…")
                    }
                }

                // Pitch and frequency dictionaries ship no term_bank files at all.
                var m = 1
                while true {
                    let filename = "term_meta_bank_\(m).json"
                    let filepath = dicDirectory.appending(component: filename)

                    guard let fileContent = try? Data(contentsOf: filepath) else {
                        break
                    }
                    try autoreleasepool {
                        let metaJson = try? JSONSerialization.jsonObject(with: fileContent)
                        guard let metaJson = metaJson as? [[Any]] else {
                            throw NSError(domain: "DictionaryImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Error decoding term metadata"])
                        }
                        let insertMeta: [TermMetaInsertion] = metaJson.compactMap({ t in
                            guard t.count >= 3,
                                  let term = t[0] as? String,
                                  let mode = t[1] as? String,
                                  let parsed = TermMetaParser.parse(mode: mode, data: t[2]),
                                  let dataEncoded = try? JSONSerialization.data(withJSONObject: t[2], options: [.fragmentsAllowed])
                            else {
                                return nil
                            }
                            return TermMetaInsertion(term: term, reading: parsed.reading, mode: mode, data: dataEncoded, dictionaryId: dictionary.id)
                        })
                        guard SQLiteManager.shared.insertTermMeta(metaInsert: insertMeta) != nil else {
                            throw NSError(domain: "DictionaryImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Error saving term metadata"])
                        }
                        importedMeta += insertMeta.count

                        m += 1

                        done += 1
                        report("Processing dictionary…")
                    }
                }

                if i == 1 && m == 1 {
                    throw NSError(domain: "DictionaryImport", code: 3, userInfo: [NSLocalizedDescriptionKey: "This dictionary contains no term or metadata banks."])
                }
                
                var summary: [String] = []
                if importedTerms > 0 {
                    summary.append("\(importedTerms.formatted()) entries")
                }
                if importedMeta > 0 {
                    summary.append("\(importedMeta.formatted()) pitch/frequency entries")
                }
                let processedMessage = "Imported \(title)\n\(summary.joined(separator: " and "))."

                // Removed only once the replacement is safely in, so a failed update can't
                // leave the user with nothing.
                if let replacing = replacing {
                    try SQLiteManager.shared.deleteDictionary(dictionaryId: replacing)
                }

                DispatchQueue.main.async {
                    if let replacing = replacing {
                        appManager.dictionaries.removeAll { $0.id == replacing }
                        appManager.dictionaries.append(dictionary)
                    }
                    appManager.setProgress(nil, for: dictionary.id)
                    appManager.setProgress(nil, for: replacing)
                }
                installed = nil
                print("riidaa: \(processedMessage)")
                appManager.purgeOrphanedEntries()
            } catch {
                appManager.setProgress(nil, for: reportingId)
                appManager.report(error: error.localizedDescription)
                return
            }
        }
    }
    
}

#Preview {
    DictionariesView()
        .environment(\.managedObjectContext, CoreDataManager.shared.container.viewContext)
        .environmentObject(AppManager.shared)
        .onAppear(perform: {
            let dic = DictionaryDB(
                id: 1,
                revision: "2025.01.10.0",
                title: "Jitandex",
                sequenced: true,
                format: 3,
                author: "Stephen Kraus",
                isUpdatable: true,
                indexUrl: "https://jitendex.org/static/yomitan.json",
                downloadUrl: "https://github.com/stephenmk/stephenmk.github.io/releases/latest/download/jitendex-yomitan.zip",
                url: "https://jitendex.org",
                description: "Jitendex is updated with new content every week. Click the 'Check for Updates' button in the Yomitan 'Dictionaries' menu to upgrade to the latest version.\n\nIf Jitendex is useful for you, please consider giving the project a star on GitHub. You can also leave a tip on Ko-fi.\nVisit https://ko-fi.com/jitendex\n\nMany thanks to everyone who has helped to fund Jitendex.\n\n• epistularum\n• 昭玄大统\n• Maciej Jur\n• Ian Strandberg\n• Kip\n• Lanwara\n• Sky\n• Adam\n• Emanuel",
                attribution: "© CC BY-SA 4.0 Stephen Kraus 2023-2025\n\nYou are free to use, modify, and redistribute Jitendex files under the terms of the Creative Commons Attribution-ShareAlike License (V4.0)\n\nJitendex includes material from several copyrighted sources in compliance with the terms and conditions of those projects.\n\n• JMdict (EDICT, etc.) dictionary data is provided by the Electronic Dictionaries Research Group. Visit edrdg.org for more information.\n• Example sentences (Japanese and English) are provided by Tatoeba (https://tatoeba.org/). This data is licensed CC BY 2.0 FR.\n• Positional information for the furigana displayed in headwords is provided by the JmdictFurigana project. This data is distributed under a Creative Commons Attribution-ShareAlike License.",
                sourceLanguage: "ja",
                targetLanguage: "en",
                frequencyMode: nil
            )
            AppManager.shared.dictionaries.append(dic)
        })
}
