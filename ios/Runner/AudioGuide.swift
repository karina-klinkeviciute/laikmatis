import AVFoundation
import Foundation
import Flutter

enum VoiceClips {
    static let phrases: [String: String] = {
        let path = FlutterDartProject.lookupKey(forAsset: "assets/voice/phrases.json")
        guard let url = Bundle.main.url(forResource: path, withExtension: nil),
              let data = try? Data(contentsOf: url),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return map
    }()
    static func url(_ text: String) throws -> URL {
        guard let file = phrases[text] else {
            throw MassageError.message("Nerastas lietuviškas pranešimas.")
        }
        let path = FlutterDartProject.lookupKey(forAsset: "assets/voice/\(file)")
        guard let url = Bundle.main.url(forResource: path, withExtension: nil) else {
            throw MassageError.message("Nerastas pranešimo garso failas.")
        }
        return url
    }
}

enum MassageError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}

func minutePhrase(_ minutes: Int) -> String {
    let noun: String
    if (11...19).contains(minutes % 100) || minutes % 10 == 0 { noun = "minučių" }
    else if minutes % 10 == 1 { noun = "minutė" }
    else { noun = "minutės" }
    return "Liko \(minutes) \(noun)"
}

func presetLabel(_ id: String) -> String {
    "\(id.hasPrefix("left") ? "Kairė" : "Dešinė") pusė, masažas \(id.hasSuffix("one") ? "vienas" : "du")"
}

/// Background playback owns the timeline. No iOS background Timer is required.
/// Spoken phrases, quiet intervals, and the final melody form one cached M4A guide.
final class AudioGuideBuilder {
    private let io = DispatchQueue(label: "lt.masazas.speech-export")
    private var cancelled = false
    private var pending: ((Result<URL, Error>) -> Void)?
    private var export: AVAssetExportSession?
    private let workspace: URL

    init() throws {
        workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    func cancel() {
        cancelled = true
        export?.cancelExport()
        let callback = pending; pending = nil
        callback?(.failure(MassageError.message("Paruošimas atšauktas.")))
    }

    func build(id: String, destination: URL,
               completion: @escaping (Result<URL, Error>) -> Void) {
        pending = completion
        Task { @MainActor in
            do {
                let duration = id.hasPrefix("left") ? 1800 : 3600
                let interval = id.hasSuffix("one") ? 60 : 300
                var phrases: [(Double, String)] = [(0, "\(presetLabel(id)). \(duration / 60) minučių. " +
                    (interval == 60 ? "Pranešimai kas minutę. Pradėta." : "Pranešimai kas penkias minutes. Pradėta."))]
                for seconds in stride(from: interval, to: duration, by: interval) {
                    phrases.append((Double(seconds), minutePhrase((duration - seconds) / 60)))
                }
                let composition = AVMutableComposition()
                guard let track = composition.addMutableTrack(withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw MassageError.message("Nepavyko paruošti garso takelio.")
                }
                for phrase in phrases {
                    try checkCancelled()
                    let url = try VoiceClips.url(phrase.1)
                    try await insert(url, at: phrase.0, into: track)
                }
                try checkCancelled()
                try await insert(makeChime(), at: Double(duration), into: track)
                let final = try VoiceClips.url("Masažas baigtas.")
                try await insert(final, at: Double(duration) + 1.4, into: track)
                try checkCancelled()
                guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
                    throw MassageError.message("Nepavyko išsaugoti garso takelio.")
                }
                export = exporter
                try? FileManager.default.removeItem(at: destination)
                exporter.outputURL = destination; exporter.outputFileType = .m4a
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    exporter.exportAsynchronously { continuation.resume() }
                }
                try checkCancelled()
                guard exporter.status == .completed else {
                    throw exporter.error ?? MassageError.message("Nepavyko paruošti garso. Patikrinkite laisvą vietą telefone.")
                }
                finish(.success(destination))
            } catch { finish(.failure(error)) }
        }
    }

    private func checkCancelled() throws {
        if cancelled { throw MassageError.message("Paruošimas atšauktas.") }
    }

    private func finish(_ outcome: Result<URL, Error>) {
        let callback = pending; pending = nil; export = nil
        callback?(outcome)
        io.async { [workspace] in try? FileManager.default.removeItem(at: workspace) }
    }

    private func insert(_ url: URL, at seconds: Double, into track: AVMutableCompositionTrack) async throws {
        let asset = AVURLAsset(url: url)
        guard let source = try await asset.loadTracks(withMediaType: .audio).first else {
            throw MassageError.message("Nepavyko atverti įgarsinto pranešimo. Įdiekite programėlę iš naujo.")
        }
        let length = try await asset.load(.duration)
        let position = CMTime(seconds: seconds, preferredTimescale: 600)
        let end = CMTimeRangeGetEnd(track.timeRange)
        if CMTimeCompare(position, end) > 0 {
            track.insertEmptyTimeRange(CMTimeRange(start: end, duration: CMTimeSubtract(position, end)))
        }
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: source, at: position)
    }

    private func makeChime() throws -> URL {
        let url = workspace.appendingPathComponent("chime.caf")
        let rate = 22050.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let count = AVAudioFrameCount(rate * 1.2)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let frequencies = [523.25, 659.25, 783.99]
        for sample in 0..<Int(count) {
            let time = Double(sample) / rate
            let note = min(2, Int(time / 0.4))
            let local = time - Double(note) * 0.4
            let envelope = min(1, local / 0.015) * max(0, 1 - local / 0.4)
            buffer.floatChannelData![0][sample] = Float(sin(2 * .pi * frequencies[note] * local) * envelope * 0.28)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}

