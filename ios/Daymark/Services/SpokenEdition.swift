//
//  SpokenEdition.swift
//  Daymark
//
//  The brief, read aloud — system voice, works over CarPlay/Bluetooth
//  as ordinary audio. Composes a script from live state and speaks it.
//

import Foundation
import AVFoundation

@MainActor
final class SpokenEdition: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false
    var onStateChange: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(script: String) {
        if isSpeaking {
            stop()
        } else {
            speak(script)
        }
    }

    private func speak(_ script: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: script)
        utterance.rate = 0.5
        utterance.postUtteranceDelay = 0.2
        synthesizer.speak(utterance)
        isSpeaking = true
        onStateChange?()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        onStateChange?()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            onStateChange?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            onStateChange?()
        }
    }
}
