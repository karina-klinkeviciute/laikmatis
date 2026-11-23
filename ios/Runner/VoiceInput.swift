import AVFoundation
import Speech
import UIKit

final class VoiceInput {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var completion: ((Result<String, Error>) -> Void)?
    private var timeout: DispatchWorkItem?
    private var tapInstalled = false
    private var recognizer: SFSpeechRecognizer?
    private var backgroundObserver: NSObjectProtocol?

    init() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.finish(.failure(MassageError.message("Balso klausymas sustabdytas išėjus iš programėlės.")))
        }
    }

    func listen(completion: @escaping (Result<String, Error>) -> Void) {
        guard SFSpeechRecognizer.supportedLocales().contains(where: {
            $0.identifier.replacingOccurrences(of: "_", with: "-").hasPrefix("lt")
        }) else {
            completion(.failure(MassageError.message("Ši „iOS“ versija nepalaiko lietuviškų balso komandų. Naudokite mygtukus ir „VoiceOver“."))); return
        }
        guard self.completion == nil else {
            completion(.failure(MassageError.message("Jau klausomasi komandos."))); return
        }
        self.completion = completion
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self, self.completion != nil else { return }
                guard status == .authorized else {
                    self.finish(.failure(MassageError.message("Balso komandoms leiskite kalbos atpažinimą telefono nustatymuose."))); return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
                    DispatchQueue.main.async {
                        guard let self = self, self.completion != nil else { return }
                        if allowed { self.begin() }
                        else { self.finish(.failure(MassageError.message("Balso komandoms suteikite mikrofono leidimą telefono nustatymuose."))) }
                    }
                }
            }
        }
    }

    private func begin() {
        guard completion != nil else { return }
        guard SFSpeechRecognizer.supportedLocales().contains(where: { $0.identifier.replacingOccurrences(of: "_", with: "-").hasPrefix("lt") }),
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "lt-LT")), recognizer.isAvailable else {
            finish(.failure(MassageError.message("Šio telefono kalbos atpažinimas nepalaiko lietuvių kalbos arba šiuo metu nepasiekiamas. Naudokite mygtukus ir „VoiceOver“."))); return
        }
        do {
            self.recognizer = recognizer
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw MassageError.message("Mikrofonas nepasiekiamas.") }
            let speechRequest = SFSpeechAudioBufferRecognitionRequest()
            speechRequest.shouldReportPartialResults = false
            request = speechRequest
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in speechRequest.append(buffer) }
            tapInstalled = true
            engine.prepare(); try engine.start()
            task = recognizer.recognitionTask(with: speechRequest) { [weak self] result, error in
                DispatchQueue.main.async {
                    if let result = result, result.isFinal { self?.finish(.success(result.bestTranscription.formattedString)) }
                    else if error != nil { self?.finish(.failure(MassageError.message("Komandos neišgirdau. Patikrinkite ryšį ir bandykite dar kartą."))) }
                }
            }
            let deadline = DispatchWorkItem { [weak self] in
                self?.finish(.failure(MassageError.message("Komandos neišgirdau. Bandykite dar kartą.")))
            }
            timeout = deadline
            DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: deadline)
        } catch { finish(.failure(error)) }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let callback = completion else { return }
        completion = nil; timeout?.cancel(); timeout = nil
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil
        recognizer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        callback(result)
    }
}
