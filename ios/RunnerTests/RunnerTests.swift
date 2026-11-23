import Flutter
import Testing
import UIKit
@testable import Runner

struct RunnerTests {

  @Test func lithuanianMinuteGrammar() {
    #expect(minutePhrase(1) == "Liko 1 minutė")
    #expect(minutePhrase(2) == "Liko 2 minutės")
    #expect(minutePhrase(11) == "Liko 11 minučių")
    #expect(minutePhrase(21) == "Liko 21 minutė")
    #expect(minutePhrase(60) == "Liko 60 minučių")
  }

  @Test func bundledCountdownRecordingsCoverEveryMinute() throws {
    #expect(VoiceClips.phrases.count == 75)
    for minute in 1...60 {
      let url = try VoiceClips.url(minutePhrase(minute))
      #expect(FileManager.default.fileExists(atPath: url.path))
    }
    #expect(try VoiceClips.url("Masažas baigtas.").pathExtension == "wav")
  }

}
