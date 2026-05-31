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
            
            if authStatus == .authorized && recordPermission {
                prepareAudioSession()
            } else {
                showError("Microphone or Speech permissions denied.")
            }
        }
    }
    
    private func prepareAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            showError("Audio Session setup failed: \(error.localizedDescription)")
        }
    }
    
    func transcribe() {
        guard !isListening && !isResetting else { return }
        
        guard let recognizer = recognizer, recognizer.isAvailable else {
            showError("Speech recognizer not available right now.")
            return
        }
        
        do {
            // 1. Teardown everything first to ensure a clean slate
            teardownAudio()
            
            // 2. Setup Engine
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else { return }
            
            // 3. Setup Request
            request = SFSpeechAudioBufferRecognitionRequest()
            guard let request = request else { return }
            request.shouldReportPartialResults = true
            
            if supportsOnDevice {
                request.requiresOnDeviceRecognition = useOnDevice
            }
            
            if #available(iOS 16.0, *) {
                request.addsPunctuation = true
            }
            request.contextualStrings = ["Dobre rano", "BigCaptions"]
            
            // 4. Start Recognition Task
            lastWordsCount = 0
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }
                
                if let result = result {
                    self.handleResult(result.bestTranscription.formattedString)
                }
                
                if let error = error {
                    let nsError = error as NSError
                    // Code 203/1110 are common timeouts. We quietly restart if that happens.
                    if nsError.domain == "kAFAssistantErrorDomain" || nsError.code == 203 || nsError.code == 1110 {
                        self.restartTaskOnly()
                    } else if nsError.code != 301 && nsError.code != 4 { // Ignore manual cancellations
                        self.showError("Speech Error (\(nsError.code)): \(error.localizedDescription)")
                    }
                }
            }
            
            // 5. Connect Microphone
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
                request.append(buffer)
            }
            
            // 6. Final Kickoff
            audioEngine.prepare()
            try audioEngine.start()
            
            DispatchQueue.main.async {
                self.isListening = true
                self.errorMessage = nil
                UIApplication.shared.isIdleTimerDisabled = true
            }
            
        } catch {
            showError("Mic Start Failed: \(error.localizedDescription)")
            teardownAudio()
        }
    }
    
    private func handleResult(_ fullText: String) {
        let words = fullText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let now = Date()
        
        // If the engine sends us more words than we had before, capture the new ones
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
                if gap > 3.0 {
                    output += "\n\n"
                } else if index > 0 {
                    output += " "
                }
                
                if debugMode {
                    output += "(\(String(format: "%.1f", gap))s) "
                }
            }
            output += word.text
            prevTime = word.arrivalTime
        }
        
        DispatchQueue.main.async {
            self.transcript = output
        }
    }
    
    /// Quietly refreshes the speech task WITHOUT touching the microphone hardware.
    /// This bypasses Apple's internal task limits.
    private func restartTaskOnly() {
        task?.cancel()
        task = nil
        lastWordsCount = 0
        
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        if supportsOnDevice { request?.requiresOnDeviceRecognition = useOnDevice }
        if #available(iOS 16.0, *) { request?.addsPunctuation = true }
        request?.contextualStrings = ["Dobre rano", "BigCaptions"]
        
        guard let request = request, let recognizer = recognizer else { return }
        
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                self.handleResult(result.bestTranscription.formattedString)
            }
        }
    }
    
    /// The "Hard Reset" - cleans up all hardware resources.
    private func teardownAudio() {
        task?.cancel()
        task = nil
        request = nil
        
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
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
            
            // Full hardware reset to un-hang anything
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
        DispatchQueue.main.async {
            self.errorMessage = message
            if self.debugMode {
                self.transcript = "<< ERROR: \(message) >>\n" + self.transcript
            }
        }
    }
}
