//
//  LyricsDatabase.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import FirebaseFirestore
import Foundation

@MainActor
final class LyricsDatabase {
    static let shared = LyricsDatabase()

    private var cache: [String: [LyricLine]?] = [:]

    private init() {}

    func lyrics(title: String, artist: String, spotifyTrackID: String?) async -> [LyricLine]? {
        let keys = [
            spotifyTrackID.map(LyricsDatabaseKeys.spotifyKey),
            LyricsDatabaseKeys.metadataKey(title: title, artist: artist),
        ].compactMap { $0 }
        guard !keys.isEmpty else { return nil }

        let cacheKey = keys.joined(separator: "|")
        if let cached = cache[cacheKey] { return cached }

        FirebaseBootstrap.configureIfNeeded()
        guard FirebaseBootstrap.isConfigured else { return nil }
        let started = Date()
        switch await Self.lookup(keys: keys) {
        case .found(let lines, let source, let keyType):
            let wordSynced = lines.filter(\.hasWordTiming).count
            LyricsLog.info(
                "Lyrics database: \(source) hit via \(keyType) key in \(Self.milliseconds(since: started))ms, \(lines.count) lines (\(wordSynced) word-synced)"
            )
            cache[cacheKey] = lines
            return lines
        case .missing:
            LyricsLog.info("Lyrics database: no entry for '\(title)' / '\(artist)' (\(Self.milliseconds(since: started))ms)")
            cache[cacheKey] = .some(nil)
            return nil
        case .failed(let message):
            LyricsLog.error("Lyrics database lookup failed for '\(title)': \(message)")
            return nil
        }
    }

    private enum LookupResult: Sendable {
        case found([LyricLine], source: String, keyType: String)
        case missing
        case failed(String)
    }

    private nonisolated static func lookup(keys: [String]) async -> LookupResult {
        let database = Firestore.firestore()
        do {
            for key in keys {
                let pointer = try await database.collection("trackKeys").document(key).getDocument()
                guard let lyricsID = pointer.get("lyricsId") as? String else { continue }
                if let data = try await database.collection("lyrics").document(lyricsID).getDocument().data(),
                   let lines = LyricsDatabaseDocument.lines(from: data) {
                    return .found(lines, source: "curated", keyType: keyType(of: key))
                }
            }
            for key in keys {
                if let data = try await database.collection("generated").document(key).getDocument().data(),
                   let lines = LyricsDatabaseDocument.lines(from: data) {
                    return .found(lines, source: "generated", keyType: keyType(of: key))
                }
            }
            return .missing
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private nonisolated static func keyType(of key: String) -> String {
        String(key.prefix { $0 != ":" })
    }

    private nonisolated static func milliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }
}

enum LyricsDatabaseDocument {
    static let schemaVersion = 1

    static func lines(from data: [String: Any]) -> [LyricLine]? {
        guard integer(data["schemaVersion"]) == schemaVersion,
              let lyricsfile = data["lyricsfile"] as? String,
              let parsed = LyricsParser.parseLyricsfile(lyricsfile),
              !parsed.isEmpty else {
            return nil
        }

        let extras = ((data["extras"] as? [String: Any])?["lines"] as? [Any]) ?? []
        guard extras.count == parsed.count else { return parsed }

        return zip(parsed, extras).map { line, rawExtra in
            guard let extra = rawExtra as? [String: Any] else { return line }
            return LyricLine(
                id: line.id,
                text: line.text,
                timestamp: line.timestamp,
                endTimestamp: line.endTimestamp,
                words: line.words,
                translatedText: line.translatedText,
                background: words(extra["background"]),
                agent: extra["agent"] as? String,
                songPart: extra["songPart"] as? String
            )
        }
    }

    private static func words(_ value: Any?) -> [LyricWord] {
        guard let items = value as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let text = item["text"] as? String,
                  let start = integer(item["startMs"]), start >= 0 else {
                return nil
            }
            let end = integer(item["endMs"]).flatMap { $0 >= start ? $0 : nil }
            return LyricWord(
                text: text,
                timestamp: TimeInterval(start) / 1000,
                endTimestamp: end.map { TimeInterval($0) / 1000 }
            )
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as Int: return number
        case let number as NSNumber: return number.intValue
        default: return nil
        }
    }
}
