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
    private var handoverTimer: Timer?
    
    init() {
        // Explicitly set locale to ensure best accuracy
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
                // Prevent screen from sleeping while listening
                UIApplication.shared.isIdleTimerDisabled = true
            }
            
            // Start the handover timer to bypass the 60s Apple limit
            startHandoverTimer()
        } catch {
            print("Audio engine error: \(error)")
        }
    }
    
    private func startNewTask() {
        task?.cancel()
        task = nil
        
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        
        // Improve accuracy: Request on-device recognition if available
        if #available(iOS 13.0, *) {
            if recognizer?.supportsOnDeviceRecognition ?? false {
                request?.requiresOnDeviceRecognition = true
            }
        }
        
        if #available(iOS 16.0, *) {
            request?.addsPunctuation = true
        }
        
        // Contextual strings to help accuracy (e.g. 'Dobre rano')
        request?.contextualStrings = ["Dobre rano"]
        
        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.processWords(result.bestTranscription.formattedString)
            }
            
            if let error = error {
                let nsError = error as NSError
                // Internal timeout or limit reached: restart task to stay alive
                if nsError.domain == "kAFAssistantErrorDomain" || nsError.code == 203 || nsError.code == 1110 {
                    self.startNewTask()
                }
            }
        }
    }
    
    private func startHandoverTimer() {
        handoverTimer?.invalidate()
        // Refresh every 50 seconds to stay safely under the 60s limit
        handoverTimer = Timer.scheduledTimer(withTimeInterval: 50.0, repeats: true) { [weak self] _ in
            self?.startNewTask()
        }
    }
    
    private func processWords(_ newTranscript: String) {
        let words = newTranscript.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let now = Date()
        
        // Only append new words to the timeline
        if words.count > timedWords.count {
            for i in timedWords.count..<words.count {
                timedWords.append(TimedWord(text: words[i], arrivalTime: now))
            }
        }
        
        rebuildFormattedTranscript()
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
    
    func stopTranscribing() {
        reset()
    }
    
    private func reset() {
        DispatchQueue.main.async { 
            self.isListening = false 
            self.transcript = "" // Explicitly wipe the text
            UIApplication.shared.isIdleTimerDisabled = false
        }
        handoverTimer?.invalidate()
        handoverTimer = nil
        task?.cancel()
        task = nil
        request = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        timedWords = []
    }
}
