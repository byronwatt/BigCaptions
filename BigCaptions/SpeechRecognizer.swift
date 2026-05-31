import Foundation
import AVFoundation
import Speech
import SwiftUI

struct TimedWord: Identifiable {
    let id = UUID()
    let text: String
    let arrivalTime: Date
}

/// A highly robust helper for speech-to-text with extreme focus on hardware stability.
class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isListening: Bool = false
    @Published var debugMode: Bool = false
    @Published var useOnDevice: Bool = false
    @Published var errorMessage: String? = nil
    
    var supportsOnDevice: Bool {
        recognizer?.supportsOnDeviceRecognition ?? false
    }
    
    private let recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    
    private var timedWords: [TimedWord] = []
    private var lastWordsCount: Int = 0
    private var isResetting: Bool = false
    
    init() {
        recognizer = SFSpeechRecognizer()
        // DO NOT start hardware here to avoid white screen hangs
    }
    
    /// Entry point for starting the app. Called after UI is visible.
    func start() {
        Task {
            let authStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            let recordPermission = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            
            DispatchQueue.main.async {
                if authStatus == .authorized && recordPermission {
                    self.transcribe()
                } else {
                    self.showError("Please enable Mic & Speech in Settings.")
                }
            }
        }
    }
    
    func transcribe() {
        // Prevent double-starting or starting while resetting
        guard !isListening && !isResetting else { return }
        
        guard let recognizer = recognizer, recognizer.isAvailable else {
            showError("Speech engine not ready.")
            return
        }
        
        do {
            teardownAudio()
            
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            audioEngine = AVAudioEngine()
            request = SFSpeechAudioBufferRecognitionRequest()
            request?.shouldReportPartialResults = true
            if supportsOnDevice { request?.requiresOnDeviceRecognition = useOnDevice }
            if #available(iOS 16.0, *) { request?.addsPunctuation = true }
            request?.contextualStrings = ["Dobre rano", "BigCaptions"]
            
            lastWordsCount = 0
            task = recognizer.recognitionTask(with: request!) { [weak self] result, error in
                guard let self = self else { return }
                if let result = result { self.handleResult(result.bestTranscription.formattedString) }
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" || nsError.code == 203 || nsError.code == 1110 {
                        self.restartTaskOnly()
                    }
                }
            }
            
            let inputNode = audioEngine!.inputNode
            inputNode.removeTap(onBus: 0)
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, _) in
                self?.request?.append(buffer)
            }
            
            audioEngine!.prepare()
            try audioEngine!.start()
            
            DispatchQueue.main.async {
                self.isListening = true
                self.errorMessage = nil
                UIApplication.shared.isIdleTimerDisabled = true
            }
            
        } catch {
            showError("Mic failed: \(error.localizedDescription)")
            teardownAudio()
        }
    }
    
    private func handleResult(_ fullText: String) {
        let words = fullText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let now = Date()
        if words.count > lastWordsCount {
            for i in lastWordsCount..<words.count {
                timedWords.append(TimedWord(text: words[i], arrivalTime: now))
            }
            lastWordsCount = words.count
            rebuildTranscript()
        }
    }
    
    private func rebuildTranscript() {
        var output = ""
        var prevTime: Date?
        for (index, word) in timedWords.enumerated() {
            if let lastTime = prevTime {
                let gap = word.arrivalTime.timeIntervalSince(lastTime)
                if gap > 3.0 { output += "\n\n" } else if index > 0 { output += " " }
            }
            output += word.text
            prevTime = word.arrivalTime
        }
        DispatchQueue.main.async { self.transcript = output }
    }
    
    private func restartTaskOnly() {
        task?.cancel()
        task = nil
        lastWordsCount = 0
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        if supportsOnDevice { request?.requiresOnDeviceRecognition = useOnDevice }
        if #available(iOS 16.0, *) { request?.addsPunctuation = true }
        
        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result { self.handleResult(result.bestTranscription.formattedString) }
        }
    }
    
    private func teardownAudio() {
        task?.cancel()
        task = nil
        request = nil
        if let engine = audioEngine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
    }
    
    func clear() {
        isResetting = true
        DispatchQueue.main.async {
            self.timedWords = []
            self.lastWordsCount = 0
            self.transcript = ""
            self.errorMessage = nil
            self.stopTranscribing()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.isResetting = false
                self.transcribe()
            }
        }
    }
    
    func stopTranscribing() {
        teardownAudio()
        DispatchQueue.main.async {
            self.isListening = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async { self.errorMessage = message }
    }
}
