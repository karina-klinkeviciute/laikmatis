import Flutter
import UIKit
import AVFoundation
import MediaPlayer

final class MassageTimer: NSObject, AVAudioPlayerDelegate {
    private var phase = "idle"
    private var id = "left_one"
    private var duration = 1800.0
    private var errorText: String?
    private var player: AVAudioPlayer?
    private var announcement: AVAudioPlayer?
    private var builder: AudioGuideBuilder?
    private var generation = UUID()
    private let voiceInput = VoiceInput()
    private var observers: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var preparationTask: UIBackgroundTaskIdentifier = .invalid
    private var lastSavedSecond = -1
    private var voiceBusy = false

    override init() {
        super.init()
        restore()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            self?.pause(announce: false)
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            self?.pause(announce: false)
        })
        let remote = MPRemoteCommandCenter.shared()
        remoteTargets.append((remote.pauseCommand, remote.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.pause(announce: false) }; return .success
        }))
        remoteTargets.append((remote.playCommand, remote.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { try? self?.resume() }; return .success
        }))
        remoteTargets.append((remote.stopCommand, remote.stopCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.stop(announce: false) }; return .success
        }))
        remote.togglePlayPauseCommand.isEnabled = false
        remote.changePlaybackPositionCommand.isEnabled = false
        remote.nextTrackCommand.isEnabled = false
        remote.previousTrackCommand.isEnabled = false
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        do {
            switch call.method {
            case "snapshot": result(snapshot())
            case "start":
                guard let preset = args["id"] as? String,
                      ["left_one", "left_two", "right_one", "right_two"].contains(preset) else {
                    throw MassageError.message("Nepasirinktas masažas.")
                }
                try start(preset); result(nil)
            case "pause": pause(); result(nil)
            case "resume": try resume(); result(nil)
            case "stop": stop(); result(nil)
            case "remaining":
                try speak(phase == "idle" ? "Laikmatis nepradėtas." :
                    phase == "finished" || remaining() == 0 ? "Masažas baigtas." : minutePhrase(Int(ceil(remaining() / 60))))
                result(nil)
            case "speak": try speak(args["text"] as? String ?? ""); result(nil)
            case "voiceSettings":
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                result(nil)
            case "listen":
                guard !voiceBusy else { throw MassageError.message("Jau klausomasi komandos.") }
                voiceBusy = true
                let wasRunning = phase == "running"
                let listeningStarted = ProcessInfo.processInfo.systemUptime
                let session = generation
                if wasRunning { pause(announce: false) }
                announcement?.stop()
                voiceInput.listen { [weak self] outcome in
                    guard let self = self else { return }
                    self.voiceBusy = false
                    if wasRunning && self.phase == "paused" && self.generation == session {
                        // The massage keeps its real duration while the microphone is active.
                        let elapsed = ProcessInfo.processInfo.systemUptime - listeningStarted
                        if let player = self.player {
                            player.currentTime = min(self.duration, player.currentTime + elapsed)
                        }
                        do { try self.resume() }
                        catch { self.errorText = error.localizedDescription }
                    }
                    switch outcome {
                    case .success(let words): result(words)
                    case .failure(let error): result(FlutterError(code: "recognition", message: error.localizedDescription, details: nil))
                    }
                }
            default: result(FlutterMethodNotImplemented)
            }
        } catch { result(FlutterError(code: "timer", message: error.localizedDescription, details: nil)) }
    }

    private func activatePlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try session.setActive(true)
    }

    private func start(_ preset: String) throws {
        guard !["running", "paused", "preparing"].contains(phase) else {
            throw MassageError.message("Pirmiausia sustabdykite veikiantį laikmatį.")
        }
        announcement?.stop(); player?.stop(); player = nil
        id = preset; duration = preset.hasPrefix("left") ? 1800 : 3600
        errorText = nil
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = caches.appendingPathComponent("MassageGuides-regina-v1", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(preset).m4a")
        if FileManager.default.fileExists(atPath: destination.path) {
            do { try play(destination); return }
            catch { try? FileManager.default.removeItem(at: destination) }
        }
        let preparation = try AudioGuideBuilder()
        phase = "preparing"; builder = preparation
        let token = UUID(); generation = token
        preparationTask = UIApplication.shared.beginBackgroundTask(withName: "Prepare massage audio") { [weak self] in
            guard let self = self, self.phase == "preparing" else { return }
            self.stop(announce: false)
            self.errorText = "Garso paruošimas sustabdytas. Paruošimo metu laikykite programėlę atidarytą."
        }
        preparation.build(id: preset, destination: destination) { [weak self] outcome in
            guard let self = self, self.generation == token else { return }
            self.builder = nil; self.endPreparationTask()
            switch outcome {
            case .success(let url):
                do { try self.play(url) }
                catch { self.phase = "idle"; self.errorText = error.localizedDescription }
            case .failure(let error): self.phase = "idle"; self.errorText = error.localizedDescription
            }
        }
    }

    private func play(_ url: URL) throws {
        try activatePlayback()
        let audio = try AVAudioPlayer(contentsOf: url)
        audio.delegate = self; audio.prepareToPlay()
        guard audio.play() else { throw MassageError.message("Nepavyko paleisti masažo garso.") }
        player = audio; phase = "running"; save(); nowPlaying()
    }

    private func remaining() -> Double {
        if phase == "finished" { return 0 }
        return max(0, duration - (player?.currentTime ?? 0))
    }

    private func snapshot() -> [String: Any] {
        if phase == "running" && player?.isPlaying == false { phase = "paused" }
        if phase == "running", let time = player?.currentTime, Int(time) / 5 != lastSavedSecond {
            lastSavedSecond = Int(time) / 5; save()
        }
        var map: [String: Any] = ["phase": phase, "id": id, "remainingMs": Int(remaining() * 1000)]
        if let error = errorText { map["error"] = error }
        return map
    }

    private func pause(announce: Bool = true) {
        guard phase == "running" else { return }
        player?.pause(); phase = "paused"; save(); nowPlaying()
        if announce { try? speak("Laikmatis pristabdytas.") }
    }

    private func resume() throws {
        guard phase == "paused", let player = player else { return }
        announcement?.stop()
        try activatePlayback()
        player.volume = 1
        guard player.play() else { throw MassageError.message("Nepavyko tęsti garso. Bandykite dar kartą.") }
        phase = "running"; save(); nowPlaying()
    }

    private func stop(announce: Bool = true) {
        generation = UUID(); builder?.cancel(); builder = nil; endPreparationTask()
        player?.stop(); player = nil; announcement?.stop()
        phase = "idle"; errorText = nil
        UserDefaults.standard.removeObject(forKey: "massage-session")
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if announce { try? speak("Laikmatis sustabdytas.") }
        else { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    private func endPreparationTask() {
        if preparationTask != .invalid {
            UIApplication.shared.endBackgroundTask(preparationTask); preparationTask = .invalid
        }
    }

    private func speak(_ text: String) throws {
        let url = try VoiceClips.url(text)
        try activatePlayback()
        announcement?.stop()
        let audio = try AVAudioPlayer(contentsOf: url)
        audio.delegate = self
        announcement = audio
        // Duck the guide while the user explicitly requests a status announcement.
        player?.volume = 0.15
        guard audio.play() else { player?.volume = 1; throw MassageError.message("Nepavyko paleisti pranešimo.") }
    }

    private func nowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: presetLabel(id), MPMediaItemPropertyArtist: "Masažo laikmatis",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: min(duration, player?.currentTime ?? 0),
            MPNowPlayingInfoPropertyPlaybackRate: phase == "running" ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
    }

    private func save() {
        guard let player = player, let url = player.url else { return }
        UserDefaults.standard.set(["id": id, "url": url.path, "position": player.currentTime,
                                  "duration": duration, "phase": phase], forKey: "massage-session")
    }

    private func restore() {
        guard let data = UserDefaults.standard.dictionary(forKey: "massage-session"),
              let preset = data["id"] as? String,
              ["left_one", "left_two", "right_one", "right_two"].contains(preset),
              let path = data["url"] as? String, let position = data["position"] as? Double,
              let seconds = data["duration"] as? Double,
              FileManager.default.fileExists(atPath: path) else { return }
        do {
            player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            player?.delegate = self; player?.currentTime = position
            id = preset; duration = seconds
            if data["phase"] as? String == "finished" { phase = "finished" }
            else {
                phase = "paused"
                errorText = "Atkurta pristabdyta sesija. Programėlei nutrūkus garsas sustojo; norėdami tęsti, paspauskite „Tęsti“."
            }
        } catch { errorText = "Ankstesnio laikmačio atkurti nepavyko. Pasirinkite naują masažą." }
    }

    func audioPlayerDidFinishPlaying(_ audio: AVAudioPlayer, successfully flag: Bool) {
        if audio === announcement {
            player?.volume = 1; announcement = nil
        } else {
            phase = "finished"
            if !flag { errorText = "Garso atkūrimas nutrūko. Patikrinkite telefoną." }
            save(); nowPlaying()
        }
        if phase != "running" {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ audio: AVAudioPlayer, error: Error?) {
        if audio === announcement { player?.volume = 1; announcement = nil }
        else { pause(announce: false) }
        errorText = "Garso atkūrimas nepavyko. Pradėkite naują masažą."
    }
}
