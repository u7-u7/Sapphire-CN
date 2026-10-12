//
//  LyricsWordTimingGenerator.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

import Accelerate
import AVFoundation
import FirebaseFirestore
import Foundation
import NaturalLanguage
import Speech

@available(macOS 26.0, *)
@MainActor
final class LyricsWordTimingGenerator {
    struct Request: Sendable {
        let trackIdentity: String
        let title: String
        let artist: String
        let album: String?
        let spotifyTrackID: String?
        let durationMs: Int?
        let lines: [LyricLine]
        let processID: pid_t
    }

    static let shared = LyricsWordTimingGenerator()
    static let minimumConfidence = 0.7
    static let minimumLineCoverage = 0.85
    nonisolated static let engine = "speechtranscriber-v1"

    private var task: Task<Void, Never>?
    private var trackIdentity: String?
    private var activeTap: LyricsAudioTap?
    private var activeContinuation: AsyncStream<AnalyzerInput>.Continuation?

    private init() {}

    func start(
        request: Request,
        currentSongTime: @escaping @MainActor () -> TimeInterval?,
        isCurrentTrack: @escaping @MainActor () -> Bool,
        onGenerated: @escaping @MainActor ([LyricLine]) -> Void
    ) {
        guard trackIdentity != request.trackIdentity else { return }
        stop()
        trackIdentity = request.trackIdentity
        task = Task { [weak self] in
            await self?.run(request, currentSongTime: currentSongTime, isCurrentTrack: isCurrentTrack, onGenerated: onGenerated)
        }
    }

    func stop() {
        task?.cancel()
        activeTap?.stop()
        activeContinuation?.finish()
        activeTap = nil
        activeContinuation = nil
        task = nil
        trackIdentity = nil
    }

    private func run(
        _ request: Request,
        currentSongTime: @MainActor () -> TimeInterval?,
        isCurrentTrack: @MainActor () -> Bool,
        onGenerated: @MainActor ([LyricLine]) -> Void
    ) async {
        let label = "'\(request.title)'"
        guard SpeechTranscriber.isAvailable else {
            LyricsLog.info("Word timing for \(label) skipped: speech transcription is unavailable on this Mac")
            return
        }

        let language = Self.dominantLanguage(of: request.lines) ?? "en"
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            LyricsLog.info("Word timing for \(label) skipped: no speech model for language '\(language)'")
            return
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        do {
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                LyricsLog.info("Word timing: downloading the \(locale.identifier) speech model (one time)")
                try await installation.downloadAndInstall()
            }
        } catch {
            LyricsLog.error("Word timing for \(label) skipped: speech model install failed: \(error.localizedDescription)")
            return
        }
        guard !Task.isCancelled, isCurrentTrack() else { return }

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            LyricsLog.error("Word timing for \(label) skipped: speech model reported no audio format")
            return
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            try await analyzer.prepareToAnalyze(in: analyzerFormat)
        } catch {
            LyricsLog.error("Word timing for \(label) skipped: analyzer setup failed: \(error.localizedDescription)")
            return
        }

        let (inputs, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let feeder = LyricsAudioFeeder(outputFormat: analyzerFormat, continuation: continuation)
        let tap = LyricsAudioTap()
        guard let songTimeAtStart = currentSongTime() else { return }
        do {
            try tap.start(processID: request.processID) { buffer in feeder.consume(buffer) }
        } catch {
            continuation.finish()
            LyricsLog.error("Word timing for \(label) skipped: audio tap on pid \(request.processID) failed: \(error.localizedDescription)")
            return
        }
        activeTap = tap
        activeContinuation = continuation
        defer {
            tap.stop()
            continuation.finish()
            if activeTap === tap {
                activeTap = nil
                activeContinuation = nil
            }
        }
        LyricsLog.info("Word timing started for \(label): \(locale.identifier), pid \(request.processID), from \(Self.seconds(songTimeAtStart))")

        let results = transcriber.results
        let collector = Task.detached { () -> [RecognizedWord] in
            var heard: [RecognizedWord] = []
            do {
                for try await result in results {
                    heard.append(contentsOf: Self.words(in: result, offset: songTimeAtStart))
                }
            } catch {
                LyricsLog.error("Word timing: transcription stream ended with an error: \(error.localizedDescription)")
            }
            return heard
        }
        let analysis = Task.detached { () -> String? in
            do {
                _ = try await analyzer.analyzeSequence(inputs)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                return nil
            } catch {
                return error.localizedDescription
            }
        }

        let lastLyricEnd = request.lines
            .last { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.endTimestamp ?? $0.timestamp + LyricsWordAligner.fallbackLineDuration }
            ?? songTimeAtStart
        var endReason = "reached the last lyric line"
        while true {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled {
                endReason = "stopped (track changed)"
                break
            }
            guard isCurrentTrack(), let now = currentSongTime() else {
                endReason = "paused or track changed"
                break
            }
            let drift = now - (songTimeAtStart + feeder.secondsFed)
            if abs(drift) > 1.5 {
                endReason = "playback position jumped by \(Self.seconds(drift))"
                break
            }
            if feeder.secondsFed > 8, !feeder.hasSignal {
                endReason = "the tapped app produced no audio (it may play through a helper process)"
                break
            }
            if now > lastLyricEnd + 1 { break }
        }

        tap.stop()
        continuation.finish()
        if activeTap === tap {
            activeTap = nil
            activeContinuation = nil
        }
        if let failure = await analysis.value {
            LyricsLog.error("Word timing for \(label): analysis failed: \(failure)")
        }
        let heard = await collector.value

        let alignment = LyricsWordAligner.align(lines: request.lines, recognized: heard)
        LyricsLog.info(
            "Word timing for \(label) ended (\(endReason)) after \(Self.seconds(feeder.secondsFed)) of audio: heard \(heard.count) words, matched \(alignment.matchedWords)/\(alignment.totalWords) (\(Self.percent(alignment.confidence))), aligned \(alignment.alignedLines)/\(alignment.lyricLines) lines (\(Self.percent(alignment.lineCoverage)))"
        )
        guard alignment.confidence >= Self.minimumConfidence, alignment.lineCoverage >= Self.minimumLineCoverage else {
            LyricsLog.info(
                "Word timing for \(label) not used: needs \(Self.percent(Self.minimumConfidence)) of words matched and \(Self.percent(Self.minimumLineCoverage)) of lines aligned"
            )
            return
        }

        if isCurrentTrack() {
            onGenerated(alignment.lines)
        }

        guard FirebaseBootstrap.isConfigured else { return }

        guard let key = request.spotifyTrackID.map(LyricsDatabaseKeys.spotifyKey)
                ?? LyricsDatabaseKeys.metadataKey(title: request.title, artist: request.artist) else {
            return
        }
        let document = GeneratedDocument(
            key: key,
            lyricsfile: LyricsfileWriter.document(title: request.title, artist: request.artist, album: request.album, lines: alignment.lines),
            title: String(request.title.prefix(500)),
            artist: String(request.artist.prefix(500)),
            album: request.album.map { String($0.prefix(500)) },
            durationMs: request.durationMs,
            confidence: alignment.confidence
        )
        if let failure = await Self.upload(document) {
            LyricsLog.error("Word timing for \(label): upload failed: \(failure)")
        } else {
            LyricsLog.info("Word timing for \(label) uploaded to the lyrics database")
        }
    }

    // MARK: - Helpers

    private struct GeneratedDocument: Sendable {
        let key: String
        let lyricsfile: String
        let title: String
        let artist: String
        let album: String?
        let durationMs: Int?
        let confidence: Double
    }

    private nonisolated static func upload(_ document: GeneratedDocument) async -> String? {
        var data: [String: Any] = [
            "schemaVersion": LyricsDatabaseDocument.schemaVersion,
            "lyricsfile": document.lyricsfile,
            "title": document.title,
            "artist": document.artist,
            "confidence": document.confidence,
            "engine": engine,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        if let album = document.album, !album.isEmpty { data["album"] = album }
        if let durationMs = document.durationMs, durationMs > 0 { data["durationMs"] = durationMs }
        do {
            try await Firestore.firestore().collection("generated").document(document.key).setData(data)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private nonisolated static func words(in result: SpeechTranscriber.Result, offset: TimeInterval) -> [RecognizedWord] {
        var words: [RecognizedWord] = []
        for run in result.text.runs {
            guard let range = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] else { continue }
            let pieces = String(result.text[run.range].characters)
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
            let start = range.start.seconds
            let duration = range.duration.seconds
            guard !pieces.isEmpty, start.isFinite, duration.isFinite, duration >= 0 else { continue }
            let step = duration / Double(pieces.count)
            for (index, piece) in pieces.enumerated() {
                let pieceStart = offset + start + step * Double(index)
                words.append(RecognizedWord(text: piece, start: pieceStart, end: pieceStart + step))
            }
        }
        return words
    }

    private static func dominantLanguage(of lines: [LyricLine]) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(lines.prefix(60).map(\.text).joined(separator: "\n"))
        return recognizer.dominantLanguage?.rawValue
    }

    private nonisolated static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1fs", value)
    }

    private nonisolated static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

@available(macOS 26.0, *)
final class LyricsAudioFeeder: @unchecked Sendable {
    private let outputFormat: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var framesFed: AVAudioFramePosition = 0
    private var peak: Float = 0

    init(outputFormat: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.outputFormat = outputFormat
        self.continuation = continuation
    }

    var secondsFed: TimeInterval {
        lock.withLock { Double(framesFed) / outputFormat.sampleRate }
    }

    var hasSignal: Bool {
        lock.withLock { peak > 0.0005 }
    }

    func consume(_ input: AVAudioPCMBuffer) {
        if converter == nil || converter?.inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: outputFormat)
        }
        guard let converter, input.frameLength > 0 else { return }

        let capacity = AVAudioFrameCount(Double(input.frameLength) * outputFormat.sampleRate / input.format.sampleRate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0 else { return }

        let level = Self.peakLevel(of: input)
        let startFrame: AVAudioFramePosition = lock.withLock {
            let start = framesFed
            framesFed += AVAudioFramePosition(output.frameLength)
            peak = max(peak, level)
            return start
        }
        continuation.yield(AnalyzerInput(
            buffer: output,
            bufferStartTime: CMTime(value: startFrame, timescale: CMTimeScale(outputFormat.sampleRate))
        ))
    }

    private static func peakLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 1 }
        var level: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            var channelPeak: Float = 0
            vDSP_maxmgv(channels[channel], 1, &channelPeak, vDSP_Length(buffer.frameLength))
            level = max(level, channelPeak)
        }
        return level
    }
}
