import Foundation
import AVFoundation
import Speech
import SwiftUI

struct TimedWord {
    let text: String
    let arrivalTime: Date
}

/// A helper for transcribing speech to text using SFSpeechRecognizer.
class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isListening: Bool = false
    @Published var debugMode: Bool = false
    @Published var errorMessage: String? = nil
    
    private let recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    
    private var timedWords: [TimedWord] = []
    private var currentTaskWordCount: Int = 0
    
    init() {
        // Force English-US if system locale is wonky, but try to respect system
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
                setupAudioSession()
            }
        }
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            showError("Audio Session: \(error.localizedDescription)")
        }
    }
    
    deinit {
        reset()
    }
    
    func transcribe() {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            showError("Speech recognizer not available")
            return
        }
        
        // If already running, don't double-start
        if audioEngine != nil { return }
        
        audioEngine = AVAudioEngine()
        startNewTask()
        
        let inputNode = audioEngine!.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Remove any existing tap to be safe
        inputNode.removeTap(onBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer: AVAudioPCMBuffer, _) in
            self?.request?.append(buffer)
        }
        
        do {
            audioEngine!.prepare()
            try audioEngine!.start()
            DispatchQueue.main.async { 
                self.isListening = true 
                self.errorMessage = nil
                UIApplication.shared.isIdleTimerDisabled = true
            }
        } catch {
            showError("Audio Engine Start: \(error.localizedDescription)")
        }
    }
    
    private func startNewTask() {
        task?.cancel()
        task = nil
        currentTaskWordCount = 0
        
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        
        // Keep it flexible to avoid failures on devices with missing local models
        request?.requiresOnDeviceRecognition = false 
        
        if #available(iOS 16.0, *) {
            request?.addsPunctuation = true
        }
        
        // Recognition hints
        request?.contextualStrings = ["Dobre rano", "BigCaptions"]
        
        guard let request = request, let recognizer = recognizer else { return }
        
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.processWords(result.bestTranscription.formattedString)
            }
            
            if let error = error {
                let nsError = error as NSError
                // Don't show error if we just manually cancelled it
                if nsError.code != 301 && nsError.code != 4 {
                    // Try to recover from common timeouts
                    if nsError.domain == "kAFAssistantErrorDomain" || nsError.code == 203 || nsError.code == 1110 {
                        self.startNewTask()
                    } else {
                        self.showError("Task Error (\(nsError.code)): \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func processWords(_ newTranscript: String) {
        let words = newTranscript.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let now = Date()
        
        if words.count > currentTaskWordCount {
            for i in currentTaskWordCount..<words.count {
                timedWords.append(TimedWord(text: words[i], arrivalTime: now))
            }
            currentTaskWordCount = words.count
            rebuildFormattedTranscript()
        }
    }
    
    private func rebuildFormattedTranscript() {
        var result = ""
        var lastTime: Date?
        
        for (index, timedWord) in timedWords.enumerated() {
            if let prevTime = lastTime {
                let gap = timedWord.arrivalTime.timeIntervalSince(prevTime)
                if gap > 3.0 {
                    result += "\n\n"
                } else if index > 0 {
                    result += " "
                }
                
                if debugMode {
                    result += "(\(String(format: "%.1f", gap))s) "
                }
            }
            
            result += timedWord.text
            lastTime = timedWord.arrivalTime
        }
        
        DispatchQueue.main.async {
            self.transcript = result
        }
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.timedWords = []
            self.currentTaskWordCount = 0
            self.transcript = ""
            self.errorMessage = nil
            // Just restart the task to clear the engine's buffer
            self.startNewTask()
        }
    }
    
    func stopTranscribing() {
        reset()
    }
    
    private func reset() {
        DispatchQueue.main.async { 
            self.isListening = false 
            self.transcript = ""
            UIApplication.shared.isIdleTimerDisabled = false
        }
        task?.cancel()
        task = nil
        request = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        timedWords = []
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            // If debug mode is on, we also show it in the transcript
            if self.debugMode {
                self.transcript = "<< ERROR: \(message) >>\n" + self.transcript
            }
        }
    }
}
