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
    
    private let recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    
    private var timedWords: [TimedWord] = []
    private var currentTaskWordCount: Int = 0
    
    init() {
        recognizer = SFSpeechRecognizer(locale: Locale.current)
        
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
                try? AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
                try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            }
        }
    }
    
    deinit {
        reset()
    }
    
    func transcribe() {
        guard let recognizer = recognizer, recognizer.isAvailable else { return }
        
        audioEngine = AVAudioEngine()
        startNewTask()
        
        let inputNode = audioEngine!.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer: AVAudioPCMBuffer, _) in
            self?.request?.append(buffer)
        }
        
        do {
            audioEngine!.prepare()
            try audioEngine!.start()
            DispatchQueue.main.async { 
                self.isListening = true 
                UIApplication.shared.isIdleTimerDisabled = true
            }
        } catch {
            print("Audio engine error: \(error)")
        }
    }
    
    private func startNewTask() {
        task?.cancel()
        task = nil
        currentTaskWordCount = 0 // Reset local task counter
        
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        
        if #available(iOS 13.0, *) {
            if recognizer?.supportsOnDeviceRecognition ?? false {
                request?.requiresOnDeviceRecognition = true
            }
        }
        
        if #available(iOS 16.0, *) {
            request?.addsPunctuation = true
        }
        
        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.processWords(result.bestTranscription.formattedString)
            }
            
            if let error = error {
                let nsError = error as NSError
                // If the engine times out or hits a limit, quietly restart just the task
                if nsError.domain == "kAFAssistantErrorDomain" || nsError.code == 203 || nsError.code == 1110 {
                    self.startNewTask()
                }
            }
        }
    }
    
    private func processWords(_ newTranscript: String) {
        let words = newTranscript.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let now = Date()
        
        // Use a task-specific counter to correctly identify NEW words
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
            // We also restart the task to clear the engine's internal buffer
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
}
